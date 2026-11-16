resource "aws_lambda_function" "fn" {
  function_name    = "orders-java"
  runtime          = "java21" # java25: remove the environment block
  handler          = "com.example.Handler::handleRequest"
  role             = var.role_arn
  filename         = "build/function.zip"
  source_code_hash = filebase64sha256("build/function.zip")
  memory_size      = 1024
  timeout          = 30
  architectures    = ["arm64"]
  environment {
    variables = {
      JAVA_TOOL_OPTIONS = "-Djava.security.properties=/var/task/pq-tls/pq-tls.security -javaagent:/var/task/pq-tls/pq-tls-agent.jar"
    }
  }
}

# Layer variant: no kit in the zip.
resource "aws_lambda_layer_version" "pq_tls" {
  layer_name               = "pq-tls"
  filename                 = "build/pq-tls-layer.zip"
  source_code_hash         = filebase64sha256("build/pq-tls-layer.zip")
  compatible_runtimes      = ["java8.al2", "java8.al2023", "java11", "java11.al2023", "java17", "java17.al2023", "java21"]
  compatible_architectures = ["arm64", "x86_64"]
}

resource "aws_lambda_function" "fn_layer" {
  function_name = "orders-java-layer"
  runtime       = "java21"
  handler       = "com.example.Handler::handleRequest"
  role          = var.role_arn
  filename      = "build/function.zip"
  layers        = [aws_lambda_layer_version.pq_tls.arn]
  architectures = ["arm64"]
  environment {
    variables = {
      AWS_LAMBDA_EXEC_WRAPPER = "/opt/pq-tls/wrapper"
    }
  }
}
