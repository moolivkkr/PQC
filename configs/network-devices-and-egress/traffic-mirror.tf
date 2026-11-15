variable "source_eni_id" { type = string } # NAT instance / proxy / app host ENI (Nitro)
variable "sensor_eni_id" { type = string } # Zeek sensor ENI

resource "aws_ec2_traffic_mirror_target" "zeek" {
  network_interface_id = var.sensor_eni_id
  description          = "Zeek PQ TLS sensor"
}

resource "aws_ec2_traffic_mirror_filter" "tls" {
  description = "TLS handshakes only"
}

resource "aws_ec2_traffic_mirror_filter_rule" "egress_443" {
  traffic_mirror_filter_id = aws_ec2_traffic_mirror_filter.tls.id
  traffic_direction        = "egress"
  rule_number              = 100
  rule_action              = "accept"
  protocol                 = 6
  destination_port_range {
    from_port = 443
    to_port   = 443
  }
  source_cidr_block      = "0.0.0.0/0"
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_ec2_traffic_mirror_filter_rule" "ingress_443" {
  traffic_mirror_filter_id = aws_ec2_traffic_mirror_filter.tls.id
  traffic_direction        = "ingress"
  rule_number              = 100
  rule_action              = "accept"
  protocol                 = 6
  source_port_range {
    from_port = 443
    to_port   = 443
  }
  source_cidr_block      = "0.0.0.0/0"
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_ec2_traffic_mirror_session" "src" {
  network_interface_id     = var.source_eni_id
  traffic_mirror_target_id = aws_ec2_traffic_mirror_target.zeek.id
  traffic_mirror_filter_id = aws_ec2_traffic_mirror_filter.tls.id
  session_number           = 1
  virtual_network_id       = 4242
  # No packet_length: the hybrid ClientHello spans two segments, so don't truncate.
  description = "PQ TLS sensor"
}
