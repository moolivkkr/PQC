terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "us-east-1"
}
variable "vpc_id" { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "certificate_arn" { type = string }
variable "log_bucket" { type = string }
variable "truststore_bucket" { type = string }

locals {
  # Phase 1: TLS 1.2 + 1.3, PQ groups offered on TLS 1.3.
  # Phase 2 (after the TLS 1.2 count is zero): ELBSecurityPolicy-TLS13-1-3-PQ-2025-09
  pq_policy = "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09"
}

resource "aws_security_group" "alb" {
  name   = "alb-pq"
  vpc_id = var.vpc_id
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "alb" {
  name               = "app-pq"
  load_balancer_type = "application"
  subnets            = var.public_subnet_ids
  security_groups    = [aws_security_group.alb.id]

  access_logs {
    bucket  = var.log_bucket
    prefix  = "alb-access"
    enabled = true
  }
  # Connection logs carry tls_keyexchange (field 13).
  connection_logs {
    bucket  = var.log_bucket
    prefix  = "alb-conn"
    enabled = true
  }
}

# Backend leg: HTTPS to targets. The ALB picks the backend policy itself
# (ELBSecurityPolicy-TLS13-1-0-PQ-2025-09 when a listener uses a PQ policy).
resource "aws_lb_target_group" "app_https" {
  name        = "app-https"
  port        = 8443
  protocol    = "HTTPS"
  target_type = "ip"
  vpc_id      = var.vpc_id
  health_check {
    protocol = "HTTPS"
    path     = "/healthz"
    matcher  = "200"
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = local.pq_policy
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_https.arn
  }
}

# Optional: mutual TLS (verify mode) on a second ALB listener.
resource "aws_lb_trust_store" "clients" {
  name                             = "client-ca"
  ca_certificates_bundle_s3_bucket = var.truststore_bucket
  ca_certificates_bundle_s3_key    = "ca-bundle.pem"
}

resource "aws_lb_listener" "https_mtls" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 8443
  protocol          = "HTTPS"
  ssl_policy        = local.pq_policy
  certificate_arn   = var.certificate_arn

  mutual_authentication {
    mode            = "verify"
    trust_store_arn = aws_lb_trust_store.clients.arn
  }

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_https.arn
  }
}

# NLB with a TLS listener (terminates TLS) and TLS to targets.
resource "aws_lb" "nlb" {
  name               = "svc-pq"
  load_balancer_type = "network"
  subnets            = var.public_subnet_ids

  access_logs {
    bucket  = var.log_bucket
    prefix  = "nlb-access"
    enabled = true
  }
}

resource "aws_lb_target_group" "svc_tls" {
  name        = "svc-tls"
  port        = 8443
  protocol    = "TLS"
  target_type = "ip"
  vpc_id      = var.vpc_id
}

resource "aws_lb_listener" "tls" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = 443
  protocol          = "TLS"
  ssl_policy        = local.pq_policy
  certificate_arn   = var.certificate_arn
  alpn_policy       = "HTTP2Preferred"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.svc_tls.arn
  }
}

# Posture: flag any HTTPS/TLS listener not on a PQ policy.
resource "aws_config_config_rule" "elb_pq" {
  name = "elbv2-pq-security-policy"
  source {
    owner             = "AWS"
    source_identifier = "ELBV2_PREDEFINED_SECURITY_POLICY_SSL_CHECK"
  }
  input_parameters = jsonencode({
    sslPolicies = join(",", [
      "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09",
      "ELBSecurityPolicy-TLS13-1-2-Res-FIPS-PQ-2025-09",
      "ELBSecurityPolicy-TLS13-1-3-PQ-2025-09",
      "ELBSecurityPolicy-TLS13-1-3-FIPS-PQ-2025-09",
    ])
  })
  scope {
    compliance_resource_types = ["AWS::ElasticLoadBalancingV2::Listener"]
  }
}
