resource "aws_ecs_task_definition" "payments_api" {
  family                   = "payments-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn
  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }
  container_definitions = jsonencode([{
    name         = "api"
    image        = var.image # repo@sha256:digest
    essential    = true
    portMappings = [{ containerPort = 8443, protocol = "tcp" }, { containerPort = 9443, protocol = "tcp" }]
    environment  = [{ name = "GODEBUG", value = "tlsmlkem=1,tlssecpmlkem=1" }]
  }])
}
