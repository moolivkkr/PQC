### Pipeline

`rules/cfn/pq-tls.guard`

```text
#
# pq-tls.guard - CloudFormation Guard 3.x rules for hybrid post-quantum TLS (X25519MLKEM768).
# Use: cfn-guard validate --rules pq-tls.guard --data template.yaml
# Also usable as the rule file of an AWS::CloudFormation::GuardHook (S3 RuleLocation).
#

# ---------- shared lists ----------
let pq_elb_policies = [
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

let pq_apigw_policies = [
  "SecurityPolicy_TLS13_1_2_PQ_2025_09",
  "SecurityPolicy_TLS13_1_2_PFS_PQ_2025_09",
  "SecurityPolicy_TLS13_1_2_FIPS_PQ_2025_09",
  "SecurityPolicy_TLS13_1_2_FIPS_PFS_PQ_2025_09"
]

# Runtimes with no in-place PQ fix: upgrade.
let lambda_runtimes_blocked = [
  "nodejs18.x", "nodejs20.x", "python3.8", "java8", "dotnet6"
]
# OpenSSL 3.5 runtimes: PQ needs the pq-tls layer (OPENSSL_CONF or the exec wrapper).
let lambda_runtimes_conf = [
  "python3.12", "python3.13", "python3.14",
  "nodejs22.x", "nodejs24.x",
  "dotnet8", "dotnet10"
]
# JDK < 25: PQ needs the Bouncy Castle JSSE agent.
let lambda_runtimes_java_agent = [ "java8.al2", "java11", "java17", "java21" ]
# OpenSSL 1.1.1 Python: shim covers urllib3/botocore only (partial). Warn-level rule.
let lambda_runtimes_py_legacy = [ "python3.9", "python3.10", "python3.11" ]

let pq_conf_paths = [ "/opt/pq-tls/openssl-pq.cnf", "/opt/pq-tls/openssl-pq-node.cnf" ]

let lambda_zip = Resources.*[
  Type == "AWS::Lambda::Function"
  Properties.PackageType !exists or Properties.PackageType != "Image"
]
let sam_zip = Resources.*[
  Type == "AWS::Serverless::Function"
  Properties.PackageType !exists or Properties.PackageType != "Image"
]

# ---------- Lambda ----------
rule PQ_LAMBDA_RUNTIME_NOT_BLOCKED when %lambda_zip !empty {
  %lambda_zip.Properties.Runtime not in %lambda_runtimes_blocked
  <<
    PQ-L1: Lambda runtime has no PQ path (Node.js 18/20 bundle OpenSSL 3.0; python3.8, java8 on AL1, dotnet6 are end of life).
    Fix: move to nodejs22.x/24.x, python3.12+, java21+agent or java25, dotnet8/10.
  >>
}

rule PQ_LAMBDA_OPENSSL_CONF when %lambda_zip !empty {
  let conf_fns = %lambda_zip[ Properties.Runtime in %lambda_runtimes_conf ]
  when %conf_fns !empty {
    %conf_fns {
      Properties.Environment.Variables exists
      Properties.Environment.Variables.OPENSSL_CONF in %pq_conf_paths or
      Properties.Environment.Variables.AWS_LAMBDA_EXEC_WRAPPER == "/opt/pq-tls/wrapper"
      <<
        PQ-L2: python3.12+/nodejs22+/dotnet8+ on AL2023 omit ML-KEM from the default group list.
        Fix: attach the pq-tls layer and set OPENSSL_CONF=/opt/pq-tls/openssl-pq.cnf (Node: openssl-pq-node.cnf)
        or AWS_LAMBDA_EXEC_WRAPPER=/opt/pq-tls/wrapper.
      >>
    }
  }
}

rule PQ_LAMBDA_JAVA_AGENT when %lambda_zip !empty {
  let java_fns = %lambda_zip[ Properties.Runtime in %lambda_runtimes_java_agent ]
  when %java_fns !empty {
    %java_fns {
      Properties.Environment.Variables exists
      Properties.Environment.Variables.JAVA_TOOL_OPTIONS == /pq-tls-agent\.jar/ or
      Properties.Environment.Variables.AWS_LAMBDA_EXEC_WRAPPER == "/opt/pq-tls/wrapper"
      <<
        PQ-L3: JDK 8-21 have no ML-KEM TLS group. Fix: JAVA_TOOL_OPTIONS=-javaagent:/opt/pq-tls/pq-tls-agent.jar
        (Bouncy Castle JSSE) or the exec wrapper, or move to java25.
      >>
    }
  }
}

# Warn-level: run with this rule in a separate file/pass whose failures do not block.
rule PQ_LAMBDA_PY_LEGACY_SHIM when %lambda_zip !empty {
  let py_fns = %lambda_zip[ Properties.Runtime in %lambda_runtimes_py_legacy ]
  when %py_fns !empty {
    %py_fns {
      Properties.Environment.Variables.AWS_LAMBDA_EXEC_WRAPPER == "/opt/pq-tls/wrapper"
      <<
        PQ-L4 (warn): python3.9-3.11 use OpenSSL 1.1.1. The pq-tls shim covers urllib3/botocore only. Plan python3.12+.
      >>
    }
  }
}

rule PQ_LAMBDA_NO_GODEBUG_OFF when %lambda_zip !empty {
  %lambda_zip.Properties.Environment.Variables.GODEBUG !exists or
  %lambda_zip.Properties.Environment.Variables.GODEBUG != /tlsmlkem=0/
  <<
    PQ-L5: GODEBUG tlsmlkem=0 turns off X25519MLKEM768 in Go crypto/tls.
  >>
}

rule PQ_SAM_RUNTIME_NOT_BLOCKED when %sam_zip !empty {
  %sam_zip.Properties.Runtime !exists or
  %sam_zip.Properties.Runtime not in %lambda_runtimes_blocked
  << PQ-L1 (SAM): see PQ-L1. Runtime may also come from Globals.Function.Runtime; check Globals. >>
}

rule PQ_SAM_GLOBAL_RUNTIME_NOT_BLOCKED when Globals.Function.Runtime exists {
  Globals.Function.Runtime not in %lambda_runtimes_blocked
  << PQ-L1 (SAM Globals): see PQ-L1. >>
}

# ---------- ECS task definitions ----------
let ecs_tds = Resources.*[ Type == "AWS::ECS::TaskDefinition" ]

rule PQ_ECS_NO_GODEBUG_OFF when %ecs_tds !empty {
  let envs = %ecs_tds.Properties.ContainerDefinitions[*].Environment[*]
  when %envs !empty {
    %envs[ Name == "GODEBUG" ].Value != /tlsmlkem=0/
    << PQ-E1: GODEBUG tlsmlkem=0 in a task definition disables PQ in Go. >>
  }
}

rule PQ_ECS_JAVA_NAMED_GROUPS when %ecs_tds !empty {
  let jto = %ecs_tds.Properties.ContainerDefinitions[*].Environment[ Name == "JAVA_TOOL_OPTIONS" ]
  when %jto !empty {
    %jto.Value != /jdk\.tls\.namedGroups=/ or %jto.Value == /X25519MLKEM768/
    << PQ-E2: -Djdk.tls.namedGroups set without X25519MLKEM768 removes PQ on JDK 25. >>
  }
}

rule PQ_ECS_OPENSSL_CONF_NOT_CLASSICAL when %ecs_tds !empty {
  let oc = %ecs_tds.Properties.ContainerDefinitions[*].Environment[ Name == "OPENSSL_CONF" ]
  when %oc !empty {
    %oc.Value != "/dev/null"
    << PQ-E3: OPENSSL_CONF=/dev/null drops the PQ group config. Point it at the pq-tls config instead. >>
  }
}

# ---------- Load balancer listeners ----------
let tls_listeners = Resources.*[
  Type == "AWS::ElasticLoadBalancingV2::Listener"
  Properties.Protocol in ["HTTPS", "TLS"]
]

rule PQ_ELB_LISTENER_POLICY when %tls_listeners !empty {
  %tls_listeners.Properties.SslPolicy exists
  <<
    PQ-B1: HTTPS/TLS listener without SslPolicy gets ELBSecurityPolicy-2016-08 from CloudFormation (no PQ).
  >>
  %tls_listeners.Properties.SslPolicy in %pq_elb_policies
  <<
    PQ-B2: SslPolicy must be a -PQ-2025-09 policy (TLS 1.0 PQ variants excluded).
    Default choice: ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09.
  >>
}

# ---------- API Gateway ----------
let rest_domains = Resources.*[
  Type == "AWS::ApiGateway::DomainName"
  Properties.EndpointConfiguration.Types[0] != "EDGE"
]
rule PQ_APIGW_DOMAIN_POLICY when %rest_domains !empty {
  %rest_domains.Properties.SecurityPolicy in %pq_apigw_policies
  << PQ-A1: REST custom domain (Regional/Private) must use a *_PQ_2025_09 security policy. >>
  %rest_domains.Properties.EndpointAccessMode in ["BASIC", "STRICT"]
  << PQ-A2: enhanced SecurityPolicy_* policies require EndpointAccessMode (start BASIC, move to STRICT). >>
}

let rest_apis = Resources.*[
  Type == "AWS::ApiGateway::RestApi"
  Properties.EndpointConfiguration.Types[0] != "EDGE"
  Properties.DisableExecuteApiEndpoint !exists or Properties.DisableExecuteApiEndpoint != true
]
rule PQ_APIGW_RESTAPI_POLICY when %rest_apis !empty {
  %rest_apis.Properties.SecurityPolicy in %pq_apigw_policies
  << PQ-A3: Regional/Private REST API execute-api endpoint must use a *_PQ_2025_09 policy, or disable the default endpoint. >>
}

let v2_domains = Resources.*[ Type == "AWS::ApiGatewayV2::DomainName" ]
rule PQ_APIGW_V2_DOMAIN_EXCEPTION when %v2_domains !empty {
  # HTTP/WebSocket APIs support only TLS_1_2 (no PQ policy). Require a registered exception tag.
  %v2_domains.Properties.Tags.PqTlsException exists
  << PQ-A4: HTTP/WebSocket API domains cannot be PQ (TLS_1_2 only). Front with CloudFront or a REST API, or register an exception (tag PqTlsException=EXC-id). >>
}
```

`rules/cfn/guard-hook.yaml`

```yaml
AWSTemplateFormatVersion: "2010-09-09"
Description: >
  CloudFormation Guard Hook that runs pq-tls.guard on every stack and resource operation in this
  account and Region. Start with FailureMode WARN; switch to FAIL after the warn window.
  Deploy to all accounts with a service-managed StackSet.
Parameters:
  RulesBucket: { Type: String }
  RulesKey: { Type: String, Default: guard/pq-tls.guard }
  LogBucket: { Type: String }
  Mode:
    Type: String
    Default: WARN
    AllowedValues: [ WARN, FAIL ]
Resources:
  GuardHookRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: "2012-10-17"
        Statement:
          - Effect: Allow
            Principal: { Service: hooks.cloudformation.amazonaws.com }
            Action: sts:AssumeRole
      Policies:
        - PolicyName: read-rules-write-logs
          PolicyDocument:
            Version: "2012-10-17"
            Statement:
              - Effect: Allow
                Action: [ s3:GetObject, s3:GetObjectVersion, s3:ListBucket ]
                Resource:
                  - !Sub arn:aws:s3:::${RulesBucket}
                  - !Sub arn:aws:s3:::${RulesBucket}/*
              - Effect: Allow
                Action: s3:PutObject
                Resource: !Sub arn:aws:s3:::${LogBucket}/*
  PqTlsGuardHook:
    Type: AWS::CloudFormation::GuardHook
    Properties:
      Alias: Private::Guard::PqTls
      ExecutionRole: !GetAtt GuardHookRole.Arn
      FailureMode: !Ref Mode
      HookStatus: ENABLED
      LogBucket: !Ref LogBucket
      RuleLocation:
        Uri: !Sub s3://${RulesBucket}/${RulesKey}
      TargetOperations: [ RESOURCE, STACK ]
      TargetFilters:
        Actions: [ CREATE, UPDATE ]
```

`rules/opa/terraform/pq_tls.rego`

```text
# Conftest / OPA policy for `terraform show -json plan.out` output.
# Usage: conftest test --policy rules/opa/terraform --namespace terraform.pq_tls plan.json
package terraform.pq_tls

import rego.v1

pq_elb_policies := {
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
	"ELBSecurityPolicy-TLS13-1-3-FIPS-PQ-2025-09",
}

pq_apigw_policies := {
	"SecurityPolicy_TLS13_1_2_PQ_2025_09",
	"SecurityPolicy_TLS13_1_2_PFS_PQ_2025_09",
	"SecurityPolicy_TLS13_1_2_FIPS_PQ_2025_09",
	"SecurityPolicy_TLS13_1_2_FIPS_PFS_PQ_2025_09",
}

blocked_runtimes := {"nodejs18.x", "nodejs20.x", "python3.8", "java8", "dotnet6"}

conf_runtimes := {"python3.12", "python3.13", "python3.14", "nodejs22.x", "nodejs24.x", "dotnet8", "dotnet10"}

agent_runtimes := {"java8.al2", "java11", "java17", "java21"}

pq_confs := {"/opt/pq-tls/openssl-pq.cnf", "/opt/pq-tls/openssl-pq-node.cnf"}

# Resources being created or updated, with their planned values.
changed contains rc if {
	some rc in input.resource_changes
	some action in rc.change.actions
	action in {"create", "update"}
}

has_exception(rc) if rc.change.after.tags["pq-tls-exception"]

env_vars(rc) := v if {
	v := rc.change.after.environment[0].variables
} else := {}

# ---------- load balancer listeners ----------
deny contains msg if {
	some rc in changed
	rc.type in {"aws_lb_listener", "aws_alb_listener"}
	rc.change.after.protocol in {"HTTPS", "TLS"}
	not elb_ok(rc.change.after)
	not has_exception(rc)
	msg := sprintf("PQ-B2 %s: ssl_policy %v is not a -PQ-2025-09 policy (default choice ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09)", [rc.address, rc.change.after.ssl_policy])
}

# ---------- API Gateway ----------
deny contains msg if {
	some rc in changed
	rc.type == "aws_api_gateway_domain_name"
	not rc.change.after.endpoint_configuration[0].types[0] == "EDGE"
	not apigw_ok(rc.change.after)
	not has_exception(rc)
	msg := sprintf("PQ-A1 %s: security_policy %v is not a *_PQ_2025_09 policy", [rc.address, rc.change.after.security_policy])
}

warn contains msg if {
	some rc in changed
	rc.type == "aws_apigatewayv2_domain_name"
	not has_exception(rc)
	msg := sprintf("PQ-A4 %s: HTTP/WebSocket API domains support TLS_1_2 only (no PQ); register an exception or front with CloudFront", [rc.address])
}

# ---------- Lambda ----------
deny contains msg if {
	some rc in changed
	rc.type == "aws_lambda_function"
	rc.change.after.runtime in blocked_runtimes
	not has_exception(rc)
	msg := sprintf("PQ-L1 %s: runtime %s has no PQ path; upgrade", [rc.address, rc.change.after.runtime])
}

deny contains msg if {
	some rc in changed
	rc.type == "aws_lambda_function"
	rc.change.after.runtime in conf_runtimes
	not conf_ok(env_vars(rc))
	not has_exception(rc)
	msg := sprintf("PQ-L2 %s: %s needs OPENSSL_CONF=/opt/pq-tls/openssl-pq*.cnf or AWS_LAMBDA_EXEC_WRAPPER=/opt/pq-tls/wrapper", [rc.address, rc.change.after.runtime])
}

deny contains msg if {
	some rc in changed
	rc.type == "aws_lambda_function"
	rc.change.after.runtime in agent_runtimes
	not agent_ok(env_vars(rc))
	not has_exception(rc)
	msg := sprintf("PQ-L3 %s: %s needs the Bouncy Castle JSSE agent (JAVA_TOOL_OPTIONS -javaagent:/opt/pq-tls/pq-tls-agent.jar) or java25", [rc.address, rc.change.after.runtime])
}

deny contains msg if {
	some rc in changed
	rc.type == "aws_lambda_function"
	contains(object.get(env_vars(rc), "GODEBUG", ""), "tlsmlkem=0")
	msg := sprintf("PQ-L5 %s: GODEBUG tlsmlkem=0 disables PQ", [rc.address])
}

# ---------- ECS ----------
deny contains msg if {
	some rc in changed
	rc.type == "aws_ecs_task_definition"
	defs := json.unmarshal(rc.change.after.container_definitions)
	some c in defs
	some e in c.environment
	e.name == "GODEBUG"
	contains(e.value, "tlsmlkem=0")
	msg := sprintf("PQ-E1 %s container %s: GODEBUG tlsmlkem=0 disables PQ", [rc.address, c.name])
}

# ---------- helpers (a missing attribute counts as not compliant) ----------
elb_ok(after) if after.ssl_policy in pq_elb_policies

apigw_ok(after) if after.security_policy in pq_apigw_policies

conf_ok(vars) if vars.OPENSSL_CONF in pq_confs

conf_ok(vars) if vars.AWS_LAMBDA_EXEC_WRAPPER == "/opt/pq-tls/wrapper"

agent_ok(vars) if contains(object.get(vars, "JAVA_TOOL_OPTIONS", ""), "pq-tls-agent.jar")

agent_ok(vars) if vars.AWS_LAMBDA_EXEC_WRAPPER == "/opt/pq-tls/wrapper"
```

`rules/opa/terraform/pq_tls_test.rego`

```text
package terraform.pq_tls_test

import rego.v1

import data.terraform.pq_tls

rc(type, after) := {"address": sprintf("%s.x", [type]), "type": type, "change": {"actions": ["create"], "after": after}}

test_listener_pq_ok if {
	count(pq_tls.deny) == 0 with input as {"resource_changes": [rc("aws_lb_listener", {"protocol": "HTTPS", "ssl_policy": "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09"})]}
}

test_listener_classic_denied if {
	count(pq_tls.deny) == 1 with input as {"resource_changes": [rc("aws_lb_listener", {"protocol": "TLS", "ssl_policy": "ELBSecurityPolicy-TLS13-1-2-2021-06"})]}
}

test_listener_http_ignored if {
	count(pq_tls.deny) == 0 with input as {"resource_changes": [rc("aws_lb_listener", {"protocol": "HTTP", "ssl_policy": null})]}
}

test_listener_exception_tag if {
	count(pq_tls.deny) == 0 with input as {"resource_changes": [rc("aws_lb_listener", {"protocol": "HTTPS", "ssl_policy": "ELBSecurityPolicy-2016-08", "tags": {"pq-tls-exception": "EXC-0007"}})]}
}

test_lambda_python_conf_ok if {
	count(pq_tls.deny) == 0 with input as {"resource_changes": [rc("aws_lambda_function", {"runtime": "python3.13", "environment": [{"variables": {"OPENSSL_CONF": "/opt/pq-tls/openssl-pq.cnf"}}]})]}
}

test_lambda_python_no_conf_denied if {
	count(pq_tls.deny) == 1 with input as {"resource_changes": [rc("aws_lambda_function", {"runtime": "python3.12", "environment": []})]}
}

test_lambda_node20_denied if {
	count(pq_tls.deny) == 1 with input as {"resource_changes": [rc("aws_lambda_function", {"runtime": "nodejs20.x"})]}
}

test_lambda_java21_agent_ok if {
	count(pq_tls.deny) == 0 with input as {"resource_changes": [rc("aws_lambda_function", {"runtime": "java21", "environment": [{"variables": {"JAVA_TOOL_OPTIONS": "-javaagent:/opt/pq-tls/pq-tls-agent.jar"}}]})]}
}

test_ecs_godebug_denied if {
	count(pq_tls.deny) == 1 with input as {"resource_changes": [rc("aws_ecs_task_definition", {"container_definitions": "[{\"name\":\"api\",\"environment\":[{\"name\":\"GODEBUG\",\"value\":\"tlsmlkem=0\"}]}]"})]}
}

test_apigw_v2_warns if {
	count(pq_tls.warn) == 1 with input as {"resource_changes": [rc("aws_apigatewayv2_domain_name", {"domain_name": "a.example.com"})]}
}
```

`rules/checkov/pq_tls_1.yaml`

```yaml
metadata:
  id: "CKV2_PQTLS_1"
  name: "ALB HTTPS / NLB TLS listener must use a -PQ-2025-09 security policy"
  category: "ENCRYPTION"
  severity: "HIGH"
definition:
  or:
    - cond_type: attribute
      resource_types: [ aws_lb_listener, aws_alb_listener ]
      attribute: protocol
      operator: not_within
      value: [ "HTTPS", "TLS" ]
    - cond_type: attribute
      resource_types: [ aws_lb_listener, aws_alb_listener ]
      attribute: ssl_policy
      operator: within
      value:
        - ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09
        - ELBSecurityPolicy-TLS13-1-2-Res-FIPS-PQ-2025-09
        - ELBSecurityPolicy-TLS13-1-2-PQ-2025-09
        - ELBSecurityPolicy-TLS13-1-2-FIPS-PQ-2025-09
        - ELBSecurityPolicy-TLS13-1-2-Ext0-FIPS-PQ-2025-09
        - ELBSecurityPolicy-TLS13-1-2-Ext1-PQ-2025-09
        - ELBSecurityPolicy-TLS13-1-2-Ext1-FIPS-PQ-2025-09
        - ELBSecurityPolicy-TLS13-1-2-Ext2-PQ-2025-09
        - ELBSecurityPolicy-TLS13-1-2-Ext2-FIPS-PQ-2025-09
        - ELBSecurityPolicy-TLS13-1-3-PQ-2025-09
        - ELBSecurityPolicy-TLS13-1-3-FIPS-PQ-2025-09
```

`rules/checkov/pq_tls_2.yaml`

```yaml
metadata:
  id: "CKV2_PQTLS_2"
  name: "Lambda runtime must have a PQ path (no nodejs18.x/20.x, python3.8, java8, dotnet6)"
  category: "ENCRYPTION"
  severity: "HIGH"
definition:
  cond_type: attribute
  resource_types: [ aws_lambda_function ]
  attribute: runtime
  operator: not_within
  value: [ "nodejs18.x", "nodejs20.x", "python3.8", "java8", "dotnet6" ]
```

`rules/checkov/pq_tls_3.yaml`

```yaml
metadata:
  id: "CKV2_PQTLS_3"
  name: "Lambda python3.12+/nodejs22+/dotnet8+ must set the pq-tls OPENSSL_CONF or exec wrapper"
  category: "ENCRYPTION"
  severity: "MEDIUM"
definition:
  or:
    - cond_type: attribute
      resource_types: [ aws_lambda_function ]
      attribute: runtime
      operator: not_within
      value: [ "python3.12", "python3.13", "python3.14", "nodejs22.x", "nodejs24.x", "dotnet8", "dotnet10" ]
    - cond_type: attribute
      resource_types: [ aws_lambda_function ]
      attribute: environment.variables.OPENSSL_CONF
      operator: within
      value: [ "/opt/pq-tls/openssl-pq.cnf", "/opt/pq-tls/openssl-pq-node.cnf" ]
    - cond_type: attribute
      resource_types: [ aws_lambda_function ]
      attribute: environment.variables.AWS_LAMBDA_EXEC_WRAPPER
      operator: equals
      value: "/opt/pq-tls/wrapper"
```

`rules/checkov/pq_tls_4.yaml`

```yaml
metadata:
  id: "CKV2_PQTLS_4"
  name: "API Gateway REST Regional/Private custom domain must use a *_PQ_2025_09 security policy"
  category: "ENCRYPTION"
  severity: "HIGH"
definition:
  cond_type: attribute
  resource_types: [ aws_api_gateway_domain_name ]
  attribute: security_policy
  operator: within
  value:
    - SecurityPolicy_TLS13_1_2_PQ_2025_09
    - SecurityPolicy_TLS13_1_2_PFS_PQ_2025_09
    - SecurityPolicy_TLS13_1_2_FIPS_PQ_2025_09
    - SecurityPolicy_TLS13_1_2_FIPS_PFS_PQ_2025_09
```

