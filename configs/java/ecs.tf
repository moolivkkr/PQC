locals {
  pq_tls_opts = "-Djava.security.properties=/opt/pq-tls/pq-tls.security -javaagent:/opt/pq-tls/pq-tls-agent.jar"
}

resource "aws_ecs_task_definition" "app" {
  family                   = "orders-java"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = var.execution_role_arn
  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }
  container_definitions = jsonencode([{
    name         = "app"
    image        = var.image # pin by digest
    essential    = true
    portMappings = [{ containerPort = 8443, protocol = "tcp" }]
    environment  = [{ name = "JAVA_TOOL_OPTIONS", value = local.pq_tls_opts }]
  }])
}
