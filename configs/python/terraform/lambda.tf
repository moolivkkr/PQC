data "archive_file" "orders" {
  type        = "zip"
  source_dir  = "${path.module}/build" # app.py, deps, pq-tls/openssl-pq.cnf
  output_path = "${path.module}/orders.zip"
}

resource "aws_lambda_function" "orders" {
  function_name    = "orders"
  role             = var.role_arn
  runtime          = "python3.13"
  architectures    = ["arm64"]
  handler          = "app.handler"
  filename         = data.archive_file.orders.output_path
  source_code_hash = data.archive_file.orders.output_base64sha256

  environment {
    variables = {
      OPENSSL_CONF = "/var/task/pq-tls/openssl-pq.cnf"
    }
  }
}
