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
