terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

provider "aws" {
  region                      = "eu-west-1"
  access_key                  = "AKIAEXAMPLEEXAMPLE00"
  secret_key                  = "example"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}

resource "aws_lb_listener" "alb_pq" {
  load_balancer_arn = "arn:aws:elasticloadbalancing:eu-west-1:111122223333:loadbalancer/app/a/1"
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09"
  certificate_arn   = "arn:aws:acm:eu-west-1:111122223333:certificate/x"
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      status_code  = "200"
    }
  }
}

resource "aws_lambda_function" "py_pq" {
  function_name = "py-pq"
  role          = "arn:aws:iam::111122223333:role/fn"
  runtime       = "python3.13"
  handler       = "app.handler"
  filename      = "fn.zip"
  layers        = ["arn:aws:lambda:eu-west-1:111122223333:layer:pq-tls:1"]
  environment {
    variables = {
      OPENSSL_CONF = "/opt/pq-tls/openssl-pq.cnf"
    }
  }
}

resource "aws_lambda_function" "java21_pq" {
  function_name = "java21-pq"
  role          = "arn:aws:iam::111122223333:role/fn"
  runtime       = "java21"
  handler       = "a.B::handle"
  filename      = "fn.zip"
  layers        = ["arn:aws:lambda:eu-west-1:111122223333:layer:pq-tls:1"]
  environment {
    variables = {
      JAVA_TOOL_OPTIONS = "-javaagent:/opt/pq-tls/pq-tls-agent.jar"
    }
  }
}

resource "aws_api_gateway_domain_name" "api" {
  domain_name              = "api.example.com"
  regional_certificate_arn = "arn:aws:acm:eu-west-1:111122223333:certificate/x"
  security_policy          = "SecurityPolicy_TLS13_1_2_PQ_2025_09"
  endpoint_access_mode     = "BASIC"
  endpoint_configuration { types = ["REGIONAL"] }
}
