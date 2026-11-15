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
