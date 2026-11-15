# AWS WAF does not terminate TLS: the CloudFront distribution, ALB, API Gateway stage,
# AppSync API, Cognito user pool, App Runner service, Verified Access instance or Amplify app
# it is attached to does. This file: a regional web ACL on an ALB, full logging (JA3/JA4
# fingerprints are logged for CloudFront and ALB only), and a Firewall Manager policy.
terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "alb_arn" { type = string }

resource "aws_wafv2_web_acl" "app" {
  name  = "app-regional"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "aws-common"
    priority = 10
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "aws-common"
      sampled_requests_enabled   = true
    }
  }

  # Label (count, never block) requests from one known client fingerprint, e.g. a
  # legacy partner SDK you have confirmed is classical from the ALB connection logs.
  rule {
    name     = "label-known-classical-client"
    priority = 20
    action {
      count {}
    }
    statement {
      byte_match_statement {
        search_string         = "t13d1516h2_8daaf6152771_02713d6af862"
        positional_constraint = "EXACTLY"
        field_to_match {
          ja4_fingerprint {
            fallback_behavior = "NO_MATCH"
          }
        }
        text_transformation {
          priority = 0
          type     = "NONE"
        }
      }
    }
    rule_label {
      name = "pq:classical-client"
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "classical-client"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "app-regional"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = var.alb_arn
  web_acl_arn  = aws_wafv2_web_acl.app.arn
}

resource "aws_cloudwatch_log_group" "waf" {
  name              = "aws-waf-logs-app-regional" # must start with aws-waf-logs-
  retention_in_days = 90
}

resource "aws_wafv2_web_acl_logging_configuration" "app" {
  resource_arn            = aws_wafv2_web_acl.app.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]
}

# Firewall Manager: put a WAF web ACL on every ALB in the organisation. Firewall Manager
# enforces WAF, Shield Advanced, security groups, network ACLs, Network Firewall and
# third-party firewalls; it has no policy type for TLS security policies.
resource "aws_fms_policy" "waf_on_albs" {
  name                  = "waf-on-all-albs"
  exclude_resource_tags = false
  remediation_enabled   = true
  resource_type         = "AWS::ElasticLoadBalancingV2::LoadBalancer"

  security_service_policy_data {
    type = "WAFV2"
    managed_service_data = jsonencode({
      type = "WAFV2"
      preProcessRuleGroups = [{
        ruleGroupArn          = null
        overrideAction        = { type = "NONE" }
        managedRuleGroupIdentifier = {
          vendorName           = "AWS"
          managedRuleGroupName = "AWSManagedRulesCommonRuleSet"
        }
        ruleGroupType          = "ManagedRuleGroup"
        excludeRules           = []
      }]
      postProcessRuleGroups = []
      defaultAction         = { type = "ALLOW" }
      overrideCustomerWebACLAssociation = false
      loggingConfiguration = {
        logDestinationConfigs = ["arn:aws:firehose:us-east-1:111122223333:deliverystream/aws-waf-logs-central"]
      }
    })
  }
}
