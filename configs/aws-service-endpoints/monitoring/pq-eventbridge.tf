resource "aws_cloudwatch_event_rule" "non_pq_calls" {
  name = "non-pq-aws-api-calls"
  event_pattern = jsonencode({
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource  = ["kms.amazonaws.com", "secretsmanager.amazonaws.com", "sts.amazonaws.com", "iam.amazonaws.com", "acm.amazonaws.com"]
      userIdentity = { invokedBy = [{ exists = false }] }
      tlsDetails   = { keyExchange = [{ "anything-but" = { wildcard = "*MLKEM*" } }] }
    }
  })
}

resource "aws_cloudwatch_event_target" "to_sns" {
  rule = aws_cloudwatch_event_rule.non_pq_calls.name
  arn  = var.alarm_topic_arn
}
