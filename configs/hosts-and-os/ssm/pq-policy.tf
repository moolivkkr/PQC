resource "aws_ssm_document" "pq_policy" {
  name            = "PQ-SetCryptoPolicy"
  document_type   = "Command"
  document_format = "JSON"
  content         = file("${path.module}/PQ-SetCryptoPolicy.json")
}

resource "aws_ssm_association" "pq_wave" {
  name                = aws_ssm_document.pq_policy.name
  association_name    = "pq-crypto-policy-wave1"
  schedule_expression = "rate(1 day)"
  max_concurrency     = "10%"
  max_errors          = "5%"
  parameters = {
    Policy       = "DEFAULT:PQ"
    RestartUnits = "sshd"
  }
  targets {
    key    = "tag:PQRollout"
    values = ["wave1"]
  }
}

resource "aws_ssm_association" "pq_rollback" {
  name             = aws_ssm_document.pq_policy.name
  association_name = "pq-crypto-policy-rollback"
  max_concurrency  = "25%"
  max_errors       = "10%"
  parameters = {
    Policy       = "DEFAULT"
    RestartUnits = "sshd"
  }
  targets {
    key    = "tag:PQRollout"
    values = ["rollback"]
  }
}
