resource "aws_lambda_function" "orders" {
  function_name    = "orders"
  runtime          = "nodejs24.x"
  architectures    = ["arm64"]
  handler          = "index.handler"
  role             = aws_iam_role.orders.arn
  filename         = "build/function.zip" # includes pq-tls/openssl-pq-node.cnf
  source_code_hash = filebase64sha256("build/function.zip")

  environment {
    variables = {
      OPENSSL_CONF = "/var/task/pq-tls/openssl-pq-node.cnf"
      # Alternative (Tested): NODE_OPTIONS = "--openssl-config=/var/task/pq-tls/openssl-pq-node.cnf"
    }
  }
}
