data "aws_ami" "ubuntu" {
  most_recent = true

  owners = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_instance" "nat" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.nat.id]
  associate_public_ip_address = true

  source_dest_check = false

  user_data = <<-EOF
    #!/bin/bash

    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-nat.conf
    sysctl --system

    INTERFACE=$(ip route | awk '/default/ {print $5; exit}')

    iptables -t nat -A POSTROUTING -o $INTERFACE -j MASQUERADE

    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent

    netfilter-persistent save
  EOF

  tags = {
    Name        = "pharmaflow-nat"
    Project     = "PharmaFlow"
    Environment = "prod"
    Role        = "nat"
  }
}
