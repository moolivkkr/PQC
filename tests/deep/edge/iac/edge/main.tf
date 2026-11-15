# Edge and API front doors: CloudFront (viewer PQ by default, origin leg classical),
# API Gateway REST with a PQ enhanced policy, Transfer Family SFTP with ML-KEM SSH KEX.
terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "cf_certificate_arn" { type = string }  # ACM cert in us-east-1
variable "api_certificate_arn" { type = string } # Regional ACM cert
variable "origin_domain" { type = string }       # e.g. the ALB DNS name

# --- CloudFront ----------------------------------------------------------
# Forward the viewer TLS details to the origin so the origin can log keyExchange.
resource "aws_cloudfront_origin_request_policy" "tls_details" {
  name = "forward-viewer-tls-details"
  cookies_config { cookie_behavior = "none" }
  query_strings_config { query_string_behavior = "all" }
  headers_config {
    header_behavior = "allViewerAndWhitelistCloudFront"
    headers {
      items = ["CloudFront-Viewer-TLS-Details", "CloudFront-Viewer-JA4-Fingerprint"]
    }
  }
}

data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

resource "aws_cloudfront_distribution" "site" {
  enabled = true
  aliases = ["www.example.com"]

  origin {
    origin_id   = "alb"
    domain_name = var.origin_domain
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      # Highest value CloudFront offers to origins; the origin leg is classical either way.
      origin_ssl_protocols = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id         = "alb"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = data.aws_cloudfront_cache_policy.optimized.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.tls_details.id
  }

  viewer_certificate {
    acm_certificate_arn = var.cf_certificate_arn
    ssl_support_method  = "sni-only"
    # PQ is offered on every policy for TLS 1.3 viewers. Move to TLSv1.3_2025 to drop TLS 1.2.
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }
}

# --- API Gateway REST (Regional) ------------------------------------------
resource "aws_api_gateway_rest_api" "api" {
  name                 = "orders"
  security_policy      = "SecurityPolicy_TLS13_1_2_PQ_2025_09"
  endpoint_access_mode = "BASIC" # move to STRICT after checking access logs
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_domain_name" "api" {
  domain_name              = "api.example.com"
  regional_certificate_arn = var.api_certificate_arn
  security_policy          = "SecurityPolicy_TLS13_1_2_PQ_2025_09"
  endpoint_access_mode     = "BASIC"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# --- Transfer Family SFTP ---------------------------------------------------
resource "aws_transfer_server" "sftp" {
  protocols              = ["SFTP"]
  identity_provider_type = "SERVICE_MANAGED"
  endpoint_type          = "PUBLIC"
  # mlkem768x25519-sha256, mlkem768nistp256-sha256, mlkem1024nistp384-sha384
  security_policy_name = "TransferSecurityPolicy-2025-03"
}
