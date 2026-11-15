resource "aws_ecs_task_definition" "orders" {
  family                   = "orders"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_exec.arn
  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }
  container_definitions = jsonencode([{
    name         = "orders"
    image        = "${aws_ecr_repository.orders.repository_url}@${var.image_digest}"
    essential    = true
    portMappings = [{ containerPort = 8443, protocol = "tcp" }]
    environment = [
      { name = "NODE_ENV", value = "production" },
      # { name = "OPENSSL_CONF", value = "/etc/app/openssl-pq-node-system.cnf" }, # distro Node without DEFAULT:PQ
    ]
  }])
}
