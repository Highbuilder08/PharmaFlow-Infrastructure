# ---------------------------------------------------------
# Bastion Elastic IP
# ---------------------------------------------------------

resource "aws_eip" "bastion" {
  domain = "vpc"

  tags = {
    Name        = "pharmaflow-bastion-eip"
    Project     = "PharmaFlow"
    Environment = "prod"
  }
}

resource "aws_eip_association" "bastion" {
  instance_id   = aws_instance.bastion.id
  allocation_id = aws_eip.bastion.id
}


# ---------------------------------------------------------
# NAT Instance Elastic IP
# ---------------------------------------------------------

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name        = "pharmaflow-nat-eip"
    Project     = "PharmaFlow"
    Environment = "prod"
  }
}

resource "aws_eip_association" "nat" {
  instance_id   = aws_instance.nat.id
  allocation_id = aws_eip.nat.id
}
