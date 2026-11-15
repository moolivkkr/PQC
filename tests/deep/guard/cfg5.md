### Runtime

`rules/runtime/cloudtrail-alarm.yaml`

```yaml
AWSTemplateFormatVersion: "2010-09-09"
Description: >
  Metric filter + alarm on the organisation trail's CloudWatch Logs group: API calls to PQ-capable
  endpoints that did not negotiate ML-KEM. Pattern extends the one in the AWS KMS developer guide
  to the six services that record tlsDetails.keyExchange.
Parameters:
  TrailLogGroup: { Type: String }
  AlarmTopicArn: { Type: String }
Resources:
  NonPqApiCalls:
    Type: AWS::Logs::MetricFilter
    Properties:
      LogGroupName: !Ref TrailLogGroup
      FilterName: pq-tls-non-pq-api-calls
      FilterPattern: >-
        { (($.eventSource = "kms.amazonaws.com") || ($.eventSource = "sts.amazonaws.com") ||
        ($.eventSource = "iam.amazonaws.com") || ($.eventSource = "secretsmanager.amazonaws.com") ||
        ($.eventSource = "acm.amazonaws.com") || ($.eventSource = "payment-cryptography.amazonaws.com")) &&
        ($.userIdentity.invokedBy NOT EXISTS) &&
        (($.tlsDetails.keyExchange != "*MLKEM*") || ($.tlsDetails.keyExchange NOT EXISTS)) }
      MetricTransformations:
        - MetricNamespace: PqTls
          MetricName: NonPqApiCalls
          MetricValue: "1"
          DefaultValue: 0
  NonPqApiCallsAlarm:
    Type: AWS::CloudWatch::Alarm
    Properties:
      AlarmName: pq-tls-non-pq-api-calls
      AlarmDescription: Classical (non-ML-KEM) TLS to KMS/STS/IAM/Secrets Manager/ACM/Payment Cryptography. Run cloudtrail-non-pq.sql to find the callers.
      Namespace: PqTls
      MetricName: NonPqApiCalls
      Statistic: Sum
      Period: 3600
      EvaluationPeriods: 1
      Threshold: 1
      ComparisonOperator: GreaterThanOrEqualToThreshold
      TreatMissingData: notBreaching
      AlarmActions: [ !Ref AlarmTopicArn ]
```

`rules/runtime/cloudtrail-non-pq.sql`

```sql
-- cloudtrail-non-pq.sql
-- Callers that reached a PQ-capable AWS endpoint WITHOUT hybrid PQ key exchange.
-- tlsDetails.keyExchange is recorded only for KMS, STS, IAM, Secrets Manager, ACM and Payment Cryptography.
-- Calls an AWS service makes on your behalf carry no tlsDetails; they are excluded via invokedBy.

-- (A) CloudTrail Lake. Replace $EDS_ID with the event data store ID.
SELECT
  eventSource,
  userIdentity.arn            AS principal,
  userAgent,
  sourceIPAddress,
  tlsDetails.tlsVersion       AS tls_version,
  tlsDetails.keyExchange      AS key_exchange,
  count(*)                    AS calls
FROM $EDS_ID
WHERE eventTime > date_add('day', -7, now())
  AND eventSource IN ('kms.amazonaws.com', 'sts.amazonaws.com', 'iam.amazonaws.com',
                      'secretsmanager.amazonaws.com', 'acm.amazonaws.com',
                      'payment-cryptography.amazonaws.com')
  AND userIdentity.invokedBy IS NULL
  AND (tlsDetails.keyExchange IS NULL OR tlsDetails.keyExchange NOT LIKE '%MLKEM%')
GROUP BY 1, 2, 3, 4, 5, 6
ORDER BY calls DESC
LIMIT 500;

-- (B) Athena over the CloudTrail S3 trail. The table DDL must declare keyExchange inside tlsdetails:
--   tlsdetails STRUCT<tlsversion:STRING, ciphersuite:STRING, clienthostheader:STRING, keyexchange:STRING>
-- (the stock DDL in the Athena docs predates keyExchange; add the field, Hive JSON SerDe ignores case).
SELECT
  eventsource,
  useridentity.arn            AS principal,
  useragent,
  tlsdetails.tlsversion       AS tls_version,
  tlsdetails.keyexchange      AS key_exchange,
  count(*)                    AS calls
FROM cloudtrail_logs
WHERE timestamp >= date_format(current_date - interval '7' day, '%Y/%m/%d')
  AND eventsource IN ('kms.amazonaws.com', 'sts.amazonaws.com', 'iam.amazonaws.com',
                      'secretsmanager.amazonaws.com', 'acm.amazonaws.com',
                      'payment-cryptography.amazonaws.com')
  AND useridentity.invokedby IS NULL
  AND (tlsdetails.keyexchange IS NULL OR tlsdetails.keyexchange NOT LIKE '%MLKEM%')
GROUP BY 1, 2, 3, 4, 5
ORDER BY calls DESC
LIMIT 500;
```

`rules/runtime/eventbridge-rules.json`

```json
{
  "pq-tls-listener-changed-to-classical": {
    "source": ["aws.elasticloadbalancing"],
    "detail-type": ["AWS API Call via CloudTrail"],
    "detail": {
      "eventSource": ["elasticloadbalancing.amazonaws.com"],
      "eventName": ["CreateListener", "ModifyListener"],
      "requestParameters": {
        "sslPolicy": [{ "anything-but": { "wildcard": "ELBSecurityPolicy-TLS13-1-[23]*PQ-2025-09" } }]
      }
    }
  },
  "pq-tls-apigw-policy-changed": {
    "source": ["aws.apigateway"],
    "detail-type": ["AWS API Call via CloudTrail"],
    "detail": {
      "eventSource": ["apigateway.amazonaws.com"],
      "eventName": ["CreateDomainName", "UpdateDomainName", "CreateRestApi", "UpdateRestApi", "ImportRestApi", "PutRestApi"]
    }
  },
  "pq-tls-config-noncompliant": {
    "source": ["aws.config"],
    "detail-type": ["Config Rules Compliance Change"],
    "detail": {
      "configRuleName": [{ "prefix": "OrgConfigRule-pq-tls-" }, { "prefix": "pq-tls-" }],
      "newEvaluationResult": { "complianceType": ["NON_COMPLIANT"] }
    }
  },
  "pq-tls-guard-hook-failed": {
    "source": ["aws.cloudformation"],
    "detail-type": ["CloudFormation Hook Invocation Progress"],
    "detail": {
      "hook-type": [{ "prefix": "Private::Guard::PqTls" }]
    }
  }
}
```

`rules/runtime/elb-logs-athena.sql`

```sql
-- elb-logs-athena.sql: classical vs PQ handshakes at ALB (connection logs) and NLB (TLS access logs).

-- ALB connection logs (15 space-separated fields; tls_keyexchange = field 13).
CREATE EXTERNAL TABLE IF NOT EXISTS alb_connection_logs (
  time string, client_ip string, client_port int, listener_port int,
  tls_protocol string, tls_cipher string, tls_handshake_latency double,
  leaf_client_cert_subject string, leaf_client_cert_validity string, leaf_client_cert_serial_number string,
  tls_verify_status string, conn_trace_id string, tls_keyexchange string, elb string, ip_address string)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.RegexSerDe'
WITH SERDEPROPERTIES ('input.regex' =
  '([^ ]*) ([^ ]*) ([0-9]*) ([0-9]*) ([^ ]*) ([^ ]*) ([-.0-9]*) ("[^"]*"|[^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ?([^ ]*)? ?([^ ]*)?.*')
LOCATION 's3://LOG_BUCKET/PREFIX/AWSLogs/ACCOUNT_ID/elasticloadbalancing/REGION/';

SELECT elb, listener_port, tls_protocol, tls_keyexchange, count(*) AS conns,
       round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY elb), 1) AS pct
FROM alb_connection_logs
WHERE tls_protocol <> '-' AND tls_verify_status = 'Success'
GROUP BY 1, 2, 3, 4 ORDER BY elb, conns DESC;

-- Top classical clients (for the exception register / client upgrade list)
SELECT client_ip, tls_protocol, tls_keyexchange, count(*) AS conns
FROM alb_connection_logs
WHERE tls_protocol <> '-' AND tls_keyexchange NOT LIKE '%MLKEM%'
GROUP BY 1, 2, 3 ORDER BY conns DESC LIMIT 100;

-- NLB TLS access logs (tls_keyexchange = field 17).
CREATE EXTERNAL TABLE IF NOT EXISTS nlb_tls_logs (
  type string, version string, time string, elb string, listener string, client_port string,
  destination_port string, connection_time double, tls_handshake_time string, received_bytes bigint,
  sent_bytes bigint, incoming_tls_alert string, chosen_cert_arn string, chosen_cert_serial string,
  tls_cipher string, tls_protocol_version string, tls_keyexchange string, domain_name string,
  alpn_fe_protocol string, alpn_be_protocol string, alpn_client_preference_list string,
  tls_connection_creation_time string)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.RegexSerDe'
WITH SERDEPROPERTIES ('input.regex' =
  '([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([-.0-9]*) ([^ ]*) ([-0-9]*) ([-0-9]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ("[^"]*"|[^ ]*) ?([^ ]*)?.*')
LOCATION 's3://LOG_BUCKET/PREFIX/AWSLogs/ACCOUNT_ID/elasticloadbalancing/REGION/';

SELECT elb, tls_protocol_version, tls_keyexchange, count(*) AS conns
FROM nlb_tls_logs
WHERE tls_protocol_version <> '-'
GROUP BY 1, 2, 3 ORDER BY conns DESC;

-- Alarm feed: run hourly (EventBridge Scheduler -> Athena StartQueryExecution via Step Functions)
-- and publish the share of non-ML-KEM TLS 1.3+1.2 handshakes as a CloudWatch metric.
SELECT count_if(tls_keyexchange NOT LIKE '%MLKEM%') AS classical,
       count(*) AS total
FROM alb_connection_logs
WHERE tls_protocol <> '-'
  AND from_iso8601_timestamp(time) > now() - interval '1' hour;
```

