# rds-pg-pq.tf - hybrid PQ key exchange for RDS for PostgreSQL 18 and Aurora PostgreSQL 18
variable "enforce_pq" {
  type    = bool
  default = false
}

locals {
  ssl_groups = var.enforce_pq ? "X25519MLKEM768,SecP256r1MLKEM768" : "X25519MLKEM768,SecP256r1MLKEM768,X25519,prime256v1"
  min_tls    = var.enforce_pq ? "TLSv1.3" : "TLSv1.2"
}

resource "aws_db_parameter_group" "pg18_pq" {
  name   = "pg18-pq"
  family = "postgres18"

  parameter {
    name         = "ssl_groups"
    value        = local.ssl_groups
    apply_method = "immediate"
  }
  parameter {
    name         = "ssl_min_protocol_version"
    value        = local.min_tls
    apply_method = "immediate"
  }
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "immediate"
  }
}

resource "aws_rds_cluster_parameter_group" "aurora_pg18_pq" {
  name   = "aurora-pg18-pq"
  family = "aurora-postgresql18"

  parameter {
    name         = "ssl_groups"
    value        = local.ssl_groups
    apply_method = "immediate"
  }
  parameter {
    name         = "ssl_min_protocol_version"
    value        = local.min_tls
    apply_method = "immediate"
  }
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "immediate"
  }
}

# Attach: aws_db_instance.parameter_group_name = aws_db_parameter_group.pg18_pq.name
#         aws_rds_cluster.db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora_pg18_pq.name
