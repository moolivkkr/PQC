resource "aws_lambda_function" "legacy" {
  function_name    = "legacy"
  role             = var.role_arn
  runtime          = "python3.11"
  handler          = "app.handler"
  filename         = "legacy.zip" # app.py, pyopenssl + cryptography (built for the arch), pq-tls/pyshim/
  source_code_hash = filebase64sha256("legacy.zip")
  environment {
    variables = {
      PYTHONPATH = "/var/task/pq-tls/pyshim"
    }
  }
}
