resource "aws_lambda_function" "dotnet" {
  function_name    = "orders-api"
  runtime          = "dotnet10" # or "provided.al2023" with handler "bootstrap" for Native AOT
  handler          = "Function::Function.Handler::FunctionHandler"
  architectures    = ["arm64"]
  role             = aws_iam_role.fn.arn
  filename         = "build/orders-api.zip" # zip holds pq-tls/openssl-pq.cnf at its root
  source_code_hash = filebase64sha256("build/orders-api.zip")

  environment {
    variables = {
      OPENSSL_CONF = "/var/task/pq-tls/openssl-pq.cnf"
    }
  }
}
