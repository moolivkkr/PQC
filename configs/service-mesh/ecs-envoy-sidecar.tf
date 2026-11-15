# ecs-envoy-sidecar.tf - ECS/Fargate: self-managed Envoy sidecar doing PQ TLS for east-west calls,
# for teams that need PQ between ECS services today (Service Connect has no key-exchange setting).
# The app calls http://127.0.0.1:8080/<svc>/...; Envoy originates TLS with ecdh_curves to the peer task,
# and the peer's Envoy terminates on 8443. Image = envoyproxy/envoy with envoy.yaml baked in (Web servers tab).
variable "app_image" { type = string }
variable "envoy_image" { type = string } # e.g. <acct>.dkr.ecr.<region>.amazonaws.com/pq-envoy@sha256:...
variable "execution_role_arn" { type = string }

resource "aws_ecs_task_definition" "orders" {
  family                   = "orders"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = var.execution_role_arn
  container_definitions = jsonencode([
    {
      name         = "app"
      image        = var.app_image
      essential    = true
      environment  = [{ name = "PAYMENTS_URL", value = "http://127.0.0.1:8080/payments" }]
      dependsOn    = [{ containerName = "envoy", condition = "HEALTHY" }]
      portMappings = []
    },
    {
      name         = "envoy"
      image        = var.envoy_image
      essential    = true
      command      = ["envoy", "-c", "/etc/envoy/envoy.yaml"]
      portMappings = [{ containerPort = 8443, protocol = "tcp" }]
      healthCheck = {
        command  = ["CMD-SHELL", "curl -sf http://127.0.0.1:9901/ready || exit 1"]
        interval = 10
        retries  = 3
      }
    }
  ])
}
