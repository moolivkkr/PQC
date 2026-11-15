resource "aws_lambda_function" "payments" {
  function_name    = "payments"
  role             = var.lambda_role_arn
  runtime          = "provided.al2023"
  handler          = "bootstrap"
  architectures    = ["arm64"]
  filename         = "${path.module}/dist/function.zip"
  source_code_hash = filebase64sha256("${path.module}/dist/function.zip")

  environment {
    variables = {
      GODEBUG = "tlsmlkem=1,tlssecpmlkem=1" # only while go.mod < 1.26
    }
  }
}

resource "aws_lambda_function" "payments_image" {
  function_name = "payments-image"
  role          = var.lambda_role_arn
  package_type  = "Image"
  image_uri     = "111122223333.dkr.ecr.us-east-1.amazonaws.com/payments@sha256:<digest>"
  architectures = ["arm64"]
}
