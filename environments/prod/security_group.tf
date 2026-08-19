resource "aws_security_group" "nat" {
  name        = "pharmaflow-nat-sg"
  description = "Security group for PharmaFlow NAT instance"
  vpc_id      = aws_vpc.pharmaflow.id

  tags = {
    Name        = "pharmaflow-nat-sg"
    Project     = "PharmaFlow"
    Environment = "prod"
  }
}

resource "aws_vpc_security_group_ingress_rule" "nat_private_a" {
  security_group_id = aws_security_group.nat.id

  cidr_ipv4   = "10.23.11.0/24"
  ip_protocol = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "nat_private_c" {
  security_group_id = aws_security_group.nat.id

  cidr_ipv4   = "10.23.12.0/24"
  ip_protocol = "-1"
}

resource "aws_vpc_security_group_egress_rule" "nat_all" {
  security_group_id = aws_security_group.nat.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}
