# ---------------------------------------------------------
# WireGuard Hybrid VPN Gateway
# ---------------------------------------------------------

resource "aws_security_group" "wireguard" {
  name        = "pharmaflow-wireguard-sg"
  description = "Security group for PharmaFlow WireGuard VPN gateway"
  vpc_id      = aws_vpc.pharmaflow.id

  tags = {
    Name        = "pharmaflow-wireguard-sg"
    Project     = "PharmaFlow"
    Environment = "prod"
    Role        = "wireguard"
  }
}

# WireGuard VPN
resource "aws_vpc_security_group_ingress_rule" "wireguard_udp" {
  security_group_id = aws_security_group.wireguard.id

  cidr_ipv4   = var.admin_cidr
  from_port   = 51820
  ip_protocol = "udp"
  to_port     = 51820
}

# 관리용 SSH
resource "aws_vpc_security_group_ingress_rule" "wireguard_ssh" {
  security_group_id = aws_security_group.wireguard.id

  cidr_ipv4   = var.admin_cidr
  from_port   = 22
  ip_protocol = "tcp"
  to_port     = 22
}

resource "aws_vpc_security_group_egress_rule" "wireguard_all" {
  security_group_id = aws_security_group.wireguard.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

# ---------------------------------------------------------
# WireGuard EC2
# ---------------------------------------------------------

resource "aws_instance" "wireguard" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.wireguard.id]
  key_name                    = var.ec2_key_name
  associate_public_ip_address = true

  # VPN Gateway로 패킷을 전달해야 하므로 반드시 비활성화
  source_dest_check = false

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = {
    Name        = "pharmaflow-wireguard"
    Project     = "PharmaFlow"
    Environment = "prod"
    Role        = "wireguard"
  }
}

# ---------------------------------------------------------
# WireGuard Elastic IP
# ---------------------------------------------------------

resource "aws_eip" "wireguard" {
  domain = "vpc"

  tags = {
    Name        = "pharmaflow-wireguard-eip"
    Project     = "PharmaFlow"
    Environment = "prod"
  }
}

resource "aws_eip_association" "wireguard" {
  instance_id   = aws_instance.wireguard.id
  allocation_id = aws_eip.wireguard.id
}

