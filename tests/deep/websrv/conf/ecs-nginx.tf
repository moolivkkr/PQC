# ecs-nginx.tf - Fargate task running the PQ nginx image built from the Dockerfile above.
variable "image" {
  description = "ECR image by digest, e.g. 123456789012.dkr.ecr.eu-west-1.amazonaws.com/pq-nginx@sha256:..."
  type        = string
}
variable "execution_role_arn" { type = string }

resource "aws_cloudwatch_log_group" "nginx" {
  name              = "/ecs/pq-nginx"
  retention_in_days = 30
}

resource "aws_ecs_task_definition" "nginx" {
  family                   = "pq-nginx"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = var.execution_role_arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }
  container_definitions = jsonencode([{
    name         = "nginx"
    image        = var.image
    essential    = true
    portMappings = [{ containerPort = 8443, protocol = "tcp" }]
    # nginx access log carries group=$ssl_curve -> CloudWatch Logs Insights can count non-PQ handshakes
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.nginx.name
        awslogs-region        = data.aws_region.current.name
        awslogs-stream-prefix = "nginx"
      }
    }
    healthCheck = {
      command  = ["CMD-SHELL", "nginx -t || exit 1"]
      interval = 30
      retries  = 3
    }
  }])
}

data "aws_region" "current" {}
