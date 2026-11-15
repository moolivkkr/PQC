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
