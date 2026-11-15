terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

# Offline plan only: fake credentials, no AWS calls are needed for create-only resources.
provider "aws" {
  region                      = "eu-west-1"
  access_key                  = "AKIAEXAMPLEEXAMPLE00"
  secret_key                  = "example"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}

resource "aws_lb_listener" "nlb_classic" {
  load_balancer_arn = "arn:aws:elasticloadbalancing:eu-west-1:111122223333:loadbalancer/net/n/1"
  port              = 443
  protocol          = "TLS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = "arn:aws:acm:eu-west-1:111122223333:certificate/x"
  default_action {
    type             = "forward"
    target_group_arn = "arn:aws:elasticloadbalancing:eu-west-1:111122223333:targetgroup/t/1"
  }
}

resource "aws_lambda_function" "py_no_conf" {
  function_name = "py-no-conf"
  role          = "arn:aws:iam::111122223333:role/fn"
  runtime       = "python3.12"
  handler       = "app.handler"
  filename      = "fn.zip"
}

resource "aws_lambda_function" "node20" {
  function_name = "node20"
  role          = "arn:aws:iam::111122223333:role/fn"
  runtime       = "nodejs20.x"
  handler       = "index.handler"
  filename      = "fn.zip"
}

resource "aws_api_gateway_domain_name" "api" {
  domain_name              = "api.example.com"
  regional_certificate_arn = "arn:aws:acm:eu-west-1:111122223333:certificate/x"
  security_policy          = "TLS_1_2"
  endpoint_configuration { types = ["REGIONAL"] }
}

resource "aws_ecs_task_definition" "go" {
  family = "go"
  container_definitions = jsonencode([{
    name        = "api"
    image       = "111122223333.dkr.ecr.eu-west-1.amazonaws.com/api:1"
    essential   = true
    environment = [{ name = "GODEBUG", value = "tlsmlkem=0" }]
  }])
}
