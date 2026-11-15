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
