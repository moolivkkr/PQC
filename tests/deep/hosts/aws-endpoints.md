## What decides PQ here

AWS owns the server side of every AWS API endpoint. On the listed services, the endpoint prefers X25519MLKEM768 whenever the client offers it ("transparent"), so the work is on the client: the SDK, the AWS CLI, or the AWS agent that makes the call. Services AWS has not listed (Systems Manager, Lambda Invoke, CloudWatch, Step Functions, ECS, EKS, the EC2 API) should be treated as classical even from a PQ client. Source: [AWS PQ readiness (confidentiality)](https://aws.amazon.com/security/post-quantum-cryptography/aws-pq-readiness-confidentiality/), re-read 2026-11-14 (the page has no date; footer © 2026).

## Status by service

Re-read 2026-11-14. "Transparent" means nothing to configure on the AWS side.

| Service | PQ on the endpoint | CloudTrail `tlsDetails.keyExchange` | Evidence |
| --- | --- | --- | --- |
| KMS | Yes, FIPS and non-FIPS, all Regions | Yes | Documented ([KMS PQ TLS](https://docs.aws.amazon.com/kms/latest/developerguide/pqtls.html)) |
| Secrets Manager | Yes, FIPS and non-FIPS (not China Regions) | Yes | Documented ([readiness](https://aws.amazon.com/security/post-quantum-cryptography/aws-pq-readiness-confidentiality/), [SM PQ TLS](https://docs.aws.amazon.com/secretsmanager/latest/userguide/pqtls.html)) |
| STS | Yes, FIPS and non-FIPS | Yes | Documented (readiness) |
| IAM, IAM Roles Anywhere | Yes, FIPS and non-FIPS | Yes | Documented (readiness) |
| ACM | Yes, FIPS and non-FIPS | Yes | Documented (readiness) |
| Payment Cryptography | Yes | Yes | Documented (readiness) |
| S3 (all bucket types) | Yes, FIPS and non-FIPS | No: data events show TLS version and cipher; key exchange "coming soon" | Documented (readiness) |
| DynamoDB | Non-FIPS only; FIPS endpoints and DAX "coming soon" | No | Documented (readiness) |
| CodeBuild, CodePipeline, Firewall Manager, IAM Identity Center, Network Firewall (API) | Yes, FIPS and non-FIPS | "Coming soon" | Documented (readiness) |
| SQS, SNS, EventBridge, ECR, Kinesis Data Streams, CloudFormation, EBS, EFS, ElastiCache, DocumentDB, Keyspaces, Glacier, Config, EC2 Auto Scaling, EC2 Instance Connect, AppSync, DMS, SWF and others | Control plane only (the page does not define "control plane") | Mostly "coming soon" | Documented (readiness) |
| Direct Connect | API endpoints | "Coming soon" | Documented (readiness) |
| Cognito custom user pool domains | Opt-in TLS policy | Not stated | Documented (readiness) |
| API Gateway (REST), ALB, NLB, RDS, Aurora, Transfer Family SFTP | Opt-in (customer resource) | ALB/NLB logs carry `keyExchange` | See the Load balancers, Edge and Databases tabs |
| Classic Load Balancer | "No PQC plan" | n/a | Documented (readiness) |
| Systems Manager (SSM API, Parameter Store, ssmmessages, ec2messages) | **Not listed** | Unknown | Absent from the page on 2026-11-14 |
| Lambda (Invoke), Step Functions, CloudWatch (Logs, metrics), ECS, EKS, Fargate, EC2 API, Kinesis Firehose, Route 53, Organizations, SES, Athena, Glue, Bedrock, SageMaker, IoT Core, VPN | **Not listed** | Unknown | Absent from the page on 2026-11-14 |

Read "control plane only" as the management APIs. Data-plane calls (SendMessage/ReceiveMessage, Publish, PutEvents, PutRecord, image layer pulls) may still be classical. I'm not sure which ECR calls count as control plane; layer downloads go to S3-backed URLs, which are PQ-capable.

### Client posture by compute type

The endpoint only negotiates PQ if the client offers it. What the client is depends on where the code runs.

| Caller | Lambda zip | Lambda image | Fargate / ECS / EKS | EC2 |
| --- | --- | --- | --- | --- |
| AWS SDK in your code | Language tab rules (Python/.NET need `OPENSSL_CONF`; nodejs22/24 need the Node conf; Java 8–21 need the agent) | Same as the base image's TLS library | Base image's TLS library (Debian 13, Alpine 3.24, node:22/24 images are PQ by default) | Host OS rules (Hosts and OS tab) unless the runtime bundles its TLS |
| AWS CLI v2 ≥ 2.34.54 | n/a | PQ (bundled OpenSSL) | PQ (bundled OpenSSL) | PQ on Linux; macOS/Windows depend on the OS library |
| Parameters and Secrets Lambda Extension ≥ v19 | PQ to Secrets Manager (Documented); SSM endpoint not listed | Same | n/a | n/a |
| Workload Credentials Provider (formerly Secrets Manager Agent) ≥ 2.0.0 | PQ to Secrets Manager | Same | Same | Same |
| SSM Agent | n/a | n/a | n/a (ECS Exec uses it) | Offers PQ (Go 1.26), endpoint not listed |

## Client side (app level)

### AWS SDKs

From the AWS [SDKs and Tools reference: Enabling hybrid post-quantum TLS](https://docs.aws.amazon.com/sdkref/latest/guide/pqtls-details.html) (read 2026-11-14). The language tabs give the full per-runtime fix.

| SDK | PQ by default? | What to do | Evidence |
| --- | --- | --- | --- |
| Go v2 | Yes with Go ≥ 1.24 and go.mod `go` ≥ 1.24 | Upgrade the toolchain; don't set `CurvePreferences` (Go tab) | Documented; Tested (Go tab) |
| JavaScript v3 (Node.js) | Yes on Node ≥ 22.20 / 24.9 (bundled OpenSSL 3.5) | Lambda nodejs22/24: override the runtime's `OPENSSL_CONF` (Node.js tab) | Documented; Tested |
| JavaScript v3 (browser) | Follows the browser | Nothing (Mobile, desktop and CLI tab) | Documented |
| Java v2, CRT HTTP client | Yes from 2.35.11 | Use `AwsCrtHttpClient` / `AwsCrtAsyncHttpClient` (older: `.postQuantumTlsEnabled(true)`, from 2.30.22) | Documented |
| Java v1/v2, default (Apache/URLConnection) client | Only on a PQ JDK (JDK 25.0.5 Corretto/Temurin tested; JDK 27 per AWS) | Java tab (BC JSSE agent for 8–21) | Documented; Tested |
| Python (boto3) and AWS CLI v1 | Yes if the linked OpenSSL is ≥ 3.5 **and** the OS policy offers ML-KEM | AL2023: `DEFAULT:PQ` or `OPENSSL_CONF`; python.org 3.14.6+ on Windows/macOS bundles OpenSSL 3.5.7 | Documented; Tested (Python tab, and CLI v1 here) |
| .NET | Linux: OS OpenSSL ≥ 3.5; Windows/macOS: .NET 10 + OS support | .NET tab | Documented; Tested on Linux |
| Rust | Yes for service crates published after 2025-08-29 | Update crates | Documented |
| Kotlin | Yes on Linux from 1.5.78; macOS/Windows follow the OS | Update | Documented |
| C++ | Only with system OpenSSL ≥ 3.5, or opt in to the CRT client (1.11.673+) | Build with `-DUSE_CRT_HTTP_CLIENT=ON` | Documented |
| PHP, Ruby | System OpenSSL ≥ 3.5 | Run on an OpenSSL 3.5 distro / image | Documented |
| Swift SDK, SAP SDK, AWS Tools for Windows PowerShell | **No plans** | Call these services from another client if PQ is required | Documented |

### AWS CLI

- **v2:** Linux installers from **2.34.54** bundle OpenSSL 3.5.6 and prefer PQ ([sdkref](https://docs.aws.amazon.com/sdkref/latest/guide/pqtls-details.html)). Rule for pipelines: `aws --version` ≥ 2.34.54 on Linux. **Tested:** `amazon/aws-cli` 2.40.3 completed TLS to a PQ-only server and to a classical-only server.
- **v2 on macOS:** install through Homebrew with Homebrew OpenSSL ≥ 3.5 (AWS doc). The macOS `.pkg` installer is not covered by that statement; not confirmed.
- **v1:** uses the Python's `ssl`. **Tested:** aws-cli 1.46.3 on `python:3.13-slim` (Debian 13, OpenSSL 3.5.7) worked against PQ-only; on `python:3.12-slim-bookworm` (OpenSSL 3.0.22) it failed with `SSLV3_ALERT_HANDSHAKE_FAILURE`.

### Parameters and Secrets Lambda Extension

- The function calls the extension over plain HTTP on `localhost:2773`; there's no TLS on that hop.
- Extension **version 19 or later** uses hybrid PQ TLS to Secrets Manager automatically ([announcement, 2026-04-14](https://aws.amazon.com/about-aws/whats-new/2026/04/aws-secrets-manager-post-quantum-tls/)). Documented.
- Its Parameter Store calls go to the SSM endpoint, which isn't on the PQ list: assume classical.

### Workload Credentials Provider (formerly Secrets Manager Agent) and ASCP

- The Secrets Manager Agent was renamed AWS Workload Credentials Provider in June 2026 ([docs](https://docs.aws.amazon.com/secretsmanager/latest/userguide/workload-credentials-provider.html)). Version **2.0.0+** uses ML-KEM as its highest-priority group by default ([SM PQ TLS](https://docs.aws.amazon.com/secretsmanager/latest/userguide/pqtls.html)).
- AWS Secrets and Configuration Provider (ASCP, the EKS CSI provider) **2.0.0+**: PQ by default (announcement). Documented.
- The language caching libraries (Java, Python, .NET, Go) aren't named in the announcement. They use your SDK client, so the SDK row above decides.

### SSM Agent, Session Manager, EC2 Instance Connect

- The SSM Agent is Go. Its `mainline` go.mod says `go 1.26` ([go.mod](https://raw.githubusercontent.com/aws/amazon-ssm-agent/mainline/go.mod), read 2026-11-14), so current builds offer X25519MLKEM768. The SSM, ssmmessages and ec2messages endpoints aren't on the PQ list, so Session Manager and Run Command traffic should be assumed classical. Unverified (needs a capture against a real endpoint).
- EC2 Instance Connect's API is on the control-plane list. The SSH session itself is your instance's sshd (Hosts and OS tab).

## Server side

There is nothing to configure on AWS-owned endpoints. Server-side work exists only where you own the TLS policy:

- ALB/NLB listeners: Load balancers tab. API Gateway, CloudFront, Cognito custom domains, Transfer Family: Edge and API front doors tab. RDS/Aurora: Databases tab.

### FIPS endpoints

KMS, Secrets Manager, STS, IAM, ACM and S3 FIPS endpoints support PQ. DynamoDB FIPS doesn't yet. Turn FIPS endpoints on per client:

```ini
# ~/.aws/config excerpt
[default]
use_fips_endpoint = true
```

or `AWS_USE_FIPS_ENDPOINT=true`. If DynamoDB PQ matters more than FIPS for a workload, that workload can't have both today.

### VPC interface endpoints (PrivateLink)

An interface endpoint carries the TLS session to the same service front end, so the same rules should apply. AWS doesn't state this on the readiness page, and a third-party report says S3 through PrivateLink differs. Unverified: confirm with CloudTrail `keyExchange` for a KMS call made through the endpoint (`vpcEndpointId` is set in the record).

## Packaging per compute type

| Compute | What to ship | IaC |
| --- | --- | --- |
| Lambda zip | Runtime fix from the language tab; extension layer ≥ v19 | SAM: `Layers:` + `OPENSSL_CONF`; Terraform `layers`, `environment` |
| Lambda image | Base image with OpenSSL 3.5 or the language conf; AWS CLI v2 ≥ 2.34.54 if the function shells out | Dockerfile (Full configuration files) |
| ECS / Fargate / EKS | PQ-capable base image; Workload Credentials Provider ≥ 2.0.0 or ASCP ≥ 2.0.0 for secrets | Task definition / pod spec (language tabs) |
| EC2 | AWS CLI v2 ≥ 2.34.54; OS policy (Hosts and OS tab) | SSM Command document `PQ-UpgradeAwsCliV2` (below) |

## Verify

1. **Posture:** `aws --version` ≥ 2.34.54 (Linux). SDK versions per language tab. Extension layer version ≥ 19.
2. **Live (lab):** point the client at a PQ-only test server with `--endpoint-url` (as done here) and at a classical-only server; both must complete TLS.
3. **Observed (production):** CloudTrail `tlsDetails.keyExchange` for KMS, Secrets Manager, STS, IAM, Roles Anywhere, ACM and Payment Cryptography. Skip records with `userIdentity.invokedBy` set: AWS-service calls carry no `tlsDetails` ([KMS doc](https://docs.aws.amazon.com/kms/latest/developerguide/pqtls.html)).

### CloudTrail Lake: classical calls by role and account

The `keyExchange` column name is assumed to match the JSON field. Not run (no AWS account here); Unverified.

```sql
SELECT recipientAccountId, eventSource, userIdentity.arn AS caller,
       tlsDetails.keyExchange AS kx, count(*) AS calls
FROM <event-data-store-id>
WHERE eventTime > timestamp '2026-11-07 00:00:00'
  AND eventSource IN ('kms.amazonaws.com','secretsmanager.amazonaws.com','sts.amazonaws.com',
                      'iam.amazonaws.com','acm.amazonaws.com','rolesanywhere.amazonaws.com',
                      'payment-cryptography.amazonaws.com')
  AND userIdentity.invokedBy IS NULL
GROUP BY 1,2,3,4
ORDER BY calls DESC
```

Add `AND (tlsDetails.keyExchange IS NULL OR tlsDetails.keyExchange NOT LIKE '%MLKEM%')` to get only the to-do list.

### Athena over the CloudTrail S3 bucket

The AWS sample DDL declares `tlsDetails` as `struct<tlsVersion,cipherSuite,clientProvidedHostHeader>`. Add `keyExchange:string` or the column reads null. Full DDL and query in the last section. Unverified (not run).

### Alert

A CloudWatch Logs metric filter on the trail's log group is AWS's documented pattern (KMS doc), extended here to all services that log `keyExchange`:

```text
{ ($.eventSource = "kms.amazonaws.com" || $.eventSource = "secretsmanager.amazonaws.com" || $.eventSource = "sts.amazonaws.com" || $.eventSource = "iam.amazonaws.com" || $.eventSource = "acm.amazonaws.com") && ($.userIdentity.invokedBy NOT EXISTS) && (($.tlsDetails.keyExchange != "*MLKEM*") || ($.tlsDetails.keyExchange NOT EXISTS)) }
```

An EventBridge rule on "AWS API Call via CloudTrail" can do the same per call. I'm not sure EventBridge receives read-only calls such as `Decrypt` and `GetSecretValue` without extra trail settings, so the metric filter is the primary alert.

## Pitfalls and rollback

- **No server-side enforcement.** There's no IAM condition key for key exchange, so you can't deny classical calls by policy. Enforcement is client posture plus the alert.
- **Missing `tlsDetails`** on service-made calls is normal; don't alarm on them.
- **Unlisted services look fine and aren't.** SSM, Lambda Invoke, CloudWatch and Step Functions produce no `keyExchange`; don't read silence as PQ.
- **Middleboxes:** the hybrid ClientHello is about 1.1 KB larger (AWS says roughly 1,600 extra handshake bytes). Egress proxies and inspection firewalls may drop it (Network devices and egress tab).
- **Rollback** is client-side: pin the previous CLI version, or remove `OPENSSL_CONF`. The endpoints still accept classical clients.

## Full configuration files

**`monitoring/pq-metric-filter.tf`**

```hcl
variable "trail_log_group" { type = string }   # CloudTrail -> CloudWatch Logs group
variable "alarm_topic_arn" { type = string }

resource "aws_cloudwatch_log_metric_filter" "non_pq_api_calls" {
  name           = "non-pq-aws-api-calls"
  log_group_name = var.trail_log_group
  pattern        = "{ ($.eventSource = \"kms.amazonaws.com\" || $.eventSource = \"secretsmanager.amazonaws.com\" || $.eventSource = \"sts.amazonaws.com\" || $.eventSource = \"iam.amazonaws.com\" || $.eventSource = \"acm.amazonaws.com\") && ($.userIdentity.invokedBy NOT EXISTS) && (($.tlsDetails.keyExchange != \"*MLKEM*\") || ($.tlsDetails.keyExchange NOT EXISTS)) }"
  metric_transformation {
    name      = "NonPqApiCalls"
    namespace = "Security/PQC"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "non_pq_api_calls" {
  alarm_name          = "non-pq-aws-api-calls"
  namespace           = "Security/PQC"
  metric_name         = "NonPqApiCalls"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alarm_topic_arn]
}
```

**`monitoring/pq-metric-filter.yaml`** (CloudFormation)

```yaml
AWSTemplateFormatVersion: "2010-09-09"
Parameters:
  TrailLogGroup: { Type: String }
  AlarmTopicArn: { Type: String }
Resources:
  NonPqFilter:
    Type: AWS::Logs::MetricFilter
    Properties:
      LogGroupName: !Ref TrailLogGroup
      FilterName: non-pq-aws-api-calls
      FilterPattern: '{ ($.eventSource = "kms.amazonaws.com" || $.eventSource = "secretsmanager.amazonaws.com" || $.eventSource = "sts.amazonaws.com" || $.eventSource = "iam.amazonaws.com" || $.eventSource = "acm.amazonaws.com") && ($.userIdentity.invokedBy NOT EXISTS) && (($.tlsDetails.keyExchange != "*MLKEM*") || ($.tlsDetails.keyExchange NOT EXISTS)) }'
      MetricTransformations:
        - MetricNamespace: Security/PQC
          MetricName: NonPqApiCalls
          MetricValue: "1"
  NonPqAlarm:
    Type: AWS::CloudWatch::Alarm
    Properties:
      AlarmName: non-pq-aws-api-calls
      Namespace: Security/PQC
      MetricName: NonPqApiCalls
      Statistic: Sum
      Period: 300
      EvaluationPeriods: 1
      Threshold: 1
      ComparisonOperator: GreaterThanOrEqualToThreshold
      TreatMissingData: notBreaching
      AlarmActions: [!Ref AlarmTopicArn]
```

**`monitoring/pq-eventbridge.tf`** (per-call events for write APIs; see the read-only caveat above)

```hcl
resource "aws_cloudwatch_event_rule" "non_pq_calls" {
  name = "non-pq-aws-api-calls"
  event_pattern = jsonencode({
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["kms.amazonaws.com", "secretsmanager.amazonaws.com", "sts.amazonaws.com", "iam.amazonaws.com", "acm.amazonaws.com"]
      userIdentity = { invokedBy = [{ exists = false }] }
      tlsDetails   = { keyExchange = [{ "anything-but" = { wildcard = "*MLKEM*" } }] }
    }
  })
}

resource "aws_cloudwatch_event_target" "to_sns" {
  rule = aws_cloudwatch_event_rule.non_pq_calls.name
  arn  = var.alarm_topic_arn
}
```

The `anything-but` + `wildcard` combination is supported in EventBridge patterns; this exact rule is untested.

**`athena/cloudtrail_pq.sql`**

```sql
-- Add keyExchange to the tlsDetails struct of the AWS sample CloudTrail table.
CREATE EXTERNAL TABLE cloudtrail_pq (
  eventVersion STRING,
  userIdentity STRUCT<type:STRING, principalId:STRING, arn:STRING, accountId:STRING, invokedBy:STRING>,
  eventTime STRING,
  eventSource STRING,
  eventName STRING,
  awsRegion STRING,
  sourceIpAddress STRING,
  userAgent STRING,
  recipientAccountId STRING,
  vpcEndpointId STRING,
  tlsDetails STRUCT<tlsVersion:STRING, cipherSuite:STRING, keyExchange:STRING, clientProvidedHostHeader:STRING>
)
PARTITIONED BY (account STRING, region STRING, day STRING)
ROW FORMAT SERDE 'org.apache.hive.hcatalog.data.JsonSerDe'
STORED AS INPUTFORMAT 'com.amazon.emr.cloudtrail.CloudTrailInputFormat'
OUTPUTFORMAT 'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION 's3://<trail-bucket>/AWSLogs/<org-id>/'
TBLPROPERTIES (
  'projection.enabled'='true',
  'projection.account.type'='enum', 'projection.account.values'='<acct1>,<acct2>',
  'projection.region.type'='enum',  'projection.region.values'='us-east-1,us-west-2',
  'projection.day.type'='date', 'projection.day.range'='2026/01/01,NOW', 'projection.day.format'='yyyy/MM/dd',
  'storage.location.template'='s3://<trail-bucket>/AWSLogs/<org-id>/${account}/CloudTrail/${region}/${day}'
);

-- Non-PQ calls by account, service and role, last 7 days.
SELECT recipientAccountId, eventSource, userIdentity.arn AS caller,
       coalesce(tlsDetails.keyExchange, '(none)') AS kx, count(*) AS calls
FROM cloudtrail_pq
WHERE day >= date_format(current_date - interval '7' day, '%Y/%m/%d')
  AND eventSource IN ('kms.amazonaws.com','secretsmanager.amazonaws.com','sts.amazonaws.com',
                      'iam.amazonaws.com','acm.amazonaws.com','rolesanywhere.amazonaws.com')
  AND userIdentity.invokedBy IS NULL
  AND (tlsDetails.keyExchange IS NULL OR tlsDetails.keyExchange NOT LIKE '%MLKEM%')
GROUP BY 1,2,3,4
ORDER BY calls DESC;
```

**`lambda/template.yaml`** (SAM: extension layer ≥ v19 plus the Python PQ conf; layer ARN per Region from the extension docs)

```yaml
AWSTemplateFormatVersion: "2010-09-09"
Transform: AWS::Serverless-2016-10-31
Parameters:
  SecretsExtensionLayerArn:
    Type: String
    Description: AWS-Parameters-and-Secrets-Lambda-Extension layer ARN for this Region, version 19 or later
  PqTlsLayerArn: { Type: String }
Resources:
  Fn:
    Type: AWS::Serverless::Function
    Properties:
      Runtime: python3.13
      Handler: app.handler
      CodeUri: src/
      Layers: [!Ref SecretsExtensionLayerArn, !Ref PqTlsLayerArn]
      Environment:
        Variables:
          OPENSSL_CONF: /opt/pq-tls/openssl-pq.cnf
          PARAMETERS_SECRETS_EXTENSION_HTTP_PORT: "2773"
      Policies:
        - AWSSecretsManagerGetSecretValuePolicy: { SecretArn: "*" }
```

**`lambda/main.tf`** (Terraform equivalent)

```hcl
resource "aws_lambda_function" "fn" {
  function_name = "pq-fn"
  runtime       = "python3.13"
  handler       = "app.handler"
  filename      = "build/fn.zip"
  role          = aws_iam_role.fn.arn
  layers        = [var.secrets_extension_layer_arn, var.pq_tls_layer_arn] # extension >= v19
  environment {
    variables = {
      OPENSSL_CONF                          = "/opt/pq-tls/openssl-pq.cnf"
      PARAMETERS_SECRETS_EXTENSION_HTTP_PORT = "2773"
    }
  }
}
```

**`images/awscli/Dockerfile`** (container or Lambda image step that needs the CLI; tested image tag `amazon/aws-cli` 2.40.3)

```dockerfile
FROM amazon/aws-cli:2.40.3 AS cli
FROM public.ecr.aws/amazonlinux/amazonlinux:2023
COPY --from=cli /usr/local/aws-cli /usr/local/aws-cli
RUN ln -s /usr/local/aws-cli/v2/current/bin/aws /usr/local/bin/aws \
 && aws --version | awk '{split($1,v,"/"); split(v[2],n,"."); if (n[1]<2 || (n[1]==2 && (n[2]<34 || (n[2]==34 && n[3]<54)))) {print "AWS CLI too old for PQ"; exit 1}}'
```

**`ssm/PQ-UpgradeAwsCliV2.json`** (SSM Command document for EC2 Linux)

```json
{
  "schemaVersion": "2.2",
  "description": "Install or upgrade AWS CLI v2 (bundles OpenSSL 3.5 from 2.34.54) and report the version.",
  "mainSteps": [
    {
      "action": "aws:runShellScript",
      "name": "upgradeAwsCli",
      "precondition": { "StringEquals": ["platformType", "Linux"] },
      "inputs": {
        "timeoutSeconds": "600",
        "runCommand": [
          "set -eu",
          "arch=$(uname -m)",
          "cd /tmp && curl -fsSL \"https://awscli.amazonaws.com/awscli-exe-linux-${arch}.zip\" -o awscliv2.zip",
          "rm -rf /tmp/aws && unzip -q awscliv2.zip",
          "/tmp/aws/install --update",
          "/usr/local/bin/aws --version"
        ]
      }
    }
  ]
}
```

**`~/.aws/config`** (FIPS endpoints, optional)

```ini
[default]
region = us-east-1
use_fips_endpoint = true
```
