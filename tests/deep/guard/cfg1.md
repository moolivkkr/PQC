## Full configuration files

Every file below is complete. Paths are relative to the rules folder. `config/lambda-pq-tls.guard` is identical to the `PolicyText` inside `org-config-rules.yaml`.

### Organisation

`rules/scp-pq-tls.json`

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyElbListenerWithoutPqPolicy",
      "Effect": "Deny",
      "Action": [
        "elasticloadbalancing:CreateListener",
        "elasticloadbalancing:ModifyListener"
      ],
      "Resource": "*",
      "Condition": {
        "Null": {
          "elasticloadbalancing:SecurityPolicy": "false"
        },
        "StringNotEquals": {
          "elasticloadbalancing:SecurityPolicy": [
            "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09",
            "ELBSecurityPolicy-TLS13-1-2-Res-FIPS-PQ-2025-09",
            "ELBSecurityPolicy-TLS13-1-2-PQ-2025-09",
            "ELBSecurityPolicy-TLS13-1-2-FIPS-PQ-2025-09",
            "ELBSecurityPolicy-TLS13-1-2-Ext0-FIPS-PQ-2025-09",
            "ELBSecurityPolicy-TLS13-1-2-Ext1-PQ-2025-09",
            "ELBSecurityPolicy-TLS13-1-2-Ext1-FIPS-PQ-2025-09",
            "ELBSecurityPolicy-TLS13-1-2-Ext2-PQ-2025-09",
            "ELBSecurityPolicy-TLS13-1-2-Ext2-FIPS-PQ-2025-09",
            "ELBSecurityPolicy-TLS13-1-3-PQ-2025-09",
            "ELBSecurityPolicy-TLS13-1-3-FIPS-PQ-2025-09"
          ]
        },
        "ArnNotLike": {
          "aws:PrincipalArn": "arn:aws:iam::*:role/pq-exception-break-glass"
        }
      }
    },
    {
      "Sid": "DenyHttpsListenerWithoutExplicitPolicy",
      "Effect": "Deny",
      "Action": "elasticloadbalancing:CreateListener",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "elasticloadbalancing:ListenerProtocol": [
            "HTTPS",
            "TLS"
          ]
        },
        "Null": {
          "elasticloadbalancing:SecurityPolicy": "true"
        },
        "ArnNotLike": {
          "aws:PrincipalArn": "arn:aws:iam::*:role/pq-exception-break-glass"
        }
      }
    },
    {
      "Sid": "DenyClassicLbListenerPolicies",
      "Effect": "Deny",
      "Action": [
        "elasticloadbalancing:CreateLoadBalancerListeners",
        "elasticloadbalancing:CreateLoadBalancerPolicy",
        "elasticloadbalancing:SetLoadBalancerPoliciesOfListener"
      ],
      "Resource": "arn:aws:elasticloadbalancing:*:*:loadbalancer/*",
      "Condition": {
        "ArnNotLike": {
          "aws:PrincipalArn": "arn:aws:iam::*:role/pq-exception-break-glass"
        }
      }
    },
    {
      "Sid": "DenyRestApiAndDomainWithoutPqPolicy",
      "Effect": "Deny",
      "Action": [
        "apigateway:POST",
        "apigateway:PATCH",
        "apigateway:PUT"
      ],
      "Resource": [
        "arn:aws:apigateway:*::/domainnames",
        "arn:aws:apigateway:*::/domainnames/*",
        "arn:aws:apigateway:*::/restapis",
        "arn:aws:apigateway:*::/restapis/*"
      ],
      "Condition": {
        "Null": {
          "apigateway:Request/SecurityPolicy": "false"
        },
        "ForAnyValue:StringNotEquals": {
          "apigateway:Request/SecurityPolicy": [
            "SecurityPolicy_TLS13_1_2_PQ_2025_09",
            "SecurityPolicy_TLS13_1_2_PFS_PQ_2025_09",
            "SecurityPolicy_TLS13_1_2_FIPS_PQ_2025_09",
            "SecurityPolicy_TLS13_1_2_FIPS_PFS_PQ_2025_09",
            "SecurityPolicy_TLS13_2025_EDGE",
            "SecurityPolicy_TLS12_PFS_2025_EDGE"
          ]
        },
        "ArnNotLike": {
          "aws:PrincipalArn": "arn:aws:iam::*:role/pq-exception-break-glass"
        }
      }
    }
  ]
}
```

`rules/rcp-s3-tls13.json`

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyS3BelowTls13ForTaggedBuckets",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::example-pq-only-bucket",
        "arn:aws:s3:::example-pq-only-bucket/*"
      ],
      "Condition": {
        "NumericLessThan": {
          "s3:TlsVersion": "1.3"
        },
        "BoolIfExists": {
          "aws:PrincipalIsAWSService": "false"
        }
      }
    }
  ]
}
```

`rules/config/org-config-rules.yaml`

```yaml
AWSTemplateFormatVersion: "2010-09-09"
Description: >
  PQ TLS detective controls for the whole organisation. Deploy in the AWS Config delegated
  administrator account, once per Region (CloudFront rule: us-east-1 only).
Parameters:
  ElbPqPolicies:
    Type: String
    Default: "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09,ELBSecurityPolicy-TLS13-1-2-Res-FIPS-PQ-2025-09,ELBSecurityPolicy-TLS13-1-2-PQ-2025-09,ELBSecurityPolicy-TLS13-1-2-FIPS-PQ-2025-09,ELBSecurityPolicy-TLS13-1-2-Ext0-FIPS-PQ-2025-09,ELBSecurityPolicy-TLS13-1-2-Ext1-PQ-2025-09,ELBSecurityPolicy-TLS13-1-2-Ext1-FIPS-PQ-2025-09,ELBSecurityPolicy-TLS13-1-2-Ext2-PQ-2025-09,ELBSecurityPolicy-TLS13-1-2-Ext2-FIPS-PQ-2025-09,ELBSecurityPolicy-TLS13-1-3-PQ-2025-09,ELBSecurityPolicy-TLS13-1-3-FIPS-PQ-2025-09"
  ApiGwPqPolicies:
    Type: String
    Default: "SecurityPolicy_TLS13_1_2_PQ_2025_09,SecurityPolicy_TLS13_1_2_PFS_PQ_2025_09,SecurityPolicy_TLS13_1_2_FIPS_PQ_2025_09,SecurityPolicy_TLS13_1_2_FIPS_PFS_PQ_2025_09,SecurityPolicy_TLS13_2025_EDGE,SecurityPolicy_TLS12_PFS_2025_EDGE"
  ExcludedAccounts:
    Type: CommaDelimitedList
    Default: ""
Conditions:
  IsUsEast1: !Equals [ !Ref "AWS::Region", us-east-1 ]
  HasExclusions: !Not [ !Equals [ !Join [ "", !Ref ExcludedAccounts ], "" ] ]
Resources:
  ElbPqPolicyRule:
    Type: AWS::Config::OrganizationConfigRule
    Properties:
      OrganizationConfigRuleName: pq-tls-elbv2-listener-policy
      ExcludedAccounts: !If [ HasExclusions, !Ref ExcludedAccounts, !Ref "AWS::NoValue" ]
      OrganizationManagedRuleMetadata:
        RuleIdentifier: ELBV2_PREDEFINED_SECURITY_POLICY_SSL_CHECK
        Description: ALB HTTPS / NLB TLS listeners must use a -PQ-2025-09 security policy
        ResourceTypesScope: [ "AWS::ElasticLoadBalancingV2::Listener" ]
        InputParameters: !Sub '{"sslPolicies":"${ElbPqPolicies}"}'
  ApiGwDomainPqRule:
    Type: AWS::Config::OrganizationConfigRule
    Properties:
      OrganizationConfigRuleName: pq-tls-apigw-domain-policy
      ExcludedAccounts: !If [ HasExclusions, !Ref ExcludedAccounts, !Ref "AWS::NoValue" ]
      OrganizationManagedRuleMetadata:
        RuleIdentifier: APIGATEWAY_DOMAIN_NAME_TLS_CHECK
        Description: API Gateway REST custom domains must use a PQ security policy
        ResourceTypesScope: [ "AWS::ApiGateway::DomainName" ]
        InputParameters: !Sub '{"allowedSecurityPolicies":"${ApiGwPqPolicies}"}'
  CloudFrontViewerPolicyRule:
    Type: AWS::Config::OrganizationConfigRule
    Condition: IsUsEast1
    Properties:
      OrganizationConfigRuleName: pq-tls-cloudfront-viewer-policy
      ExcludedAccounts: !If [ HasExclusions, !Ref ExcludedAccounts, !Ref "AWS::NoValue" ]
      OrganizationManagedRuleMetadata:
        RuleIdentifier: CLOUDFRONT_SSL_POLICY_CHECK
        Description: CloudFront viewer TLS policy must allow TLS 1.3 (PQ is negotiated only in TLS 1.3)
        ResourceTypesScope: [ "AWS::CloudFront::Distribution" ]
        InputParameters: '{"securityPolicies":"TLSv1.2_2021,TLSv1.2_2025,TLSv1.3_2025"}'
  LambdaPqRule:
    Type: AWS::Config::OrganizationConfigRule
    Properties:
      OrganizationConfigRuleName: pq-tls-lambda-runtime-env
      ExcludedAccounts: !If [ HasExclusions, !Ref ExcludedAccounts, !Ref "AWS::NoValue" ]
      OrganizationCustomPolicyRuleMetadata:
        Description: Lambda runtime has a PQ path and the pq-tls env is set
        Runtime: guard-2.x.x
        OrganizationConfigRuleTriggerTypes: [ ConfigurationItemChangeNotification ]
        ResourceTypesScope: [ "AWS::Lambda::Function" ]
        PolicyText: |
          let blocked = [ "nodejs18.x", "nodejs20.x", "python3.8", "java8", "dotnet6" ]
          let needs_conf = [ "python3.12", "python3.13", "python3.14", "nodejs22.x", "nodejs24.x", "dotnet8", "dotnet10" ]
          let needs_agent = [ "java8.al2", "java11", "java17", "java21" ]
          let pq_confs = [ "/opt/pq-tls/openssl-pq.cnf", "/opt/pq-tls/openssl-pq-node.cnf" ]
          rule lambda_runtime_has_pq_path when configuration.packageType != "Image" {
            configuration.runtime not in %blocked
          }
          rule lambda_openssl_conf_set when configuration.runtime in %needs_conf {
            configuration.environment.variables.OPENSSL_CONF in %pq_confs or
            configuration.environment.variables.AWS_LAMBDA_EXEC_WRAPPER == "/opt/pq-tls/wrapper"
          }
          rule lambda_java_agent_set when configuration.runtime in %needs_agent {
            configuration.environment.variables.JAVA_TOOL_OPTIONS == /pq-tls-agent\.jar/ or
            configuration.environment.variables.AWS_LAMBDA_EXEC_WRAPPER == "/opt/pq-tls/wrapper"
          }
          rule lambda_godebug_not_off when configuration.environment.variables.GODEBUG exists {
            configuration.environment.variables.GODEBUG != /tlsmlkem=0/
          }
```

