# traffic-mirror.tf - mirror TLS handshakes from a Nitro EC2 ENI to a Zeek sensor ENI.
# Mirrored packets arrive at the sensor as VXLAN (UDP 4789); allow that in the sensor's security group.
variable "source_eni_id" { type = string } # e.g. the NAT instance / proxy / app host ENI
variable "sensor_eni_id" { type = string } # Zeek sensor's secondary ENI (or use network_load_balancer_arn)

resource "aws_ec2_traffic_mirror_target" "zeek" {
  network_interface_id = var.sensor_eni_id
  description          = "Zeek PQ TLS sensor"
}

resource "aws_ec2_traffic_mirror_filter" "tls" {
  description = "TLS handshakes only"
}

# Outbound TLS (client hello and the rest of the flow)
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

# Return traffic (server hello carries the chosen group)
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
  # Omit packet_length to mirror whole packets; truncating cuts cost, but the
  # X25519MLKEM768 ClientHello (~1.3 KB) spans two segments, so keep at least the default MTU.
  description = "PQ TLS sensor"
}
