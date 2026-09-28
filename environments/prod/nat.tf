resource "aws_instance" "nat" {
  ami                         = var.ubuntu_ami_id
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

    iptables -t nat -C POSTROUTING -o $INTERFACE -j MASQUERADE 2>/dev/null || \
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
