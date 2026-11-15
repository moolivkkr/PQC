resource "aws_lambda_function" "fn" {
  function_name = "pq-fn"
  runtime       = "python3.13"
  handler       = "app.handler"
  filename      = "build/fn.zip"
  role          = aws_iam_role.fn.arn
  layers        = [var.secrets_extension_layer_arn, var.pq_tls_layer_arn] # extension >= v19
  environment {
    variables = {
      OPENSSL_CONF                           = "/opt/pq-tls/openssl-pq.cnf"
      PARAMETERS_SECRETS_EXTENSION_HTTP_PORT = "2773"
    }
  }
}
