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

# ---------------------------------------------------------
# Bastion Security Group
# ---------------------------------------------------------

resource "aws_security_group" "bastion" {
  name        = "pharmaflow-bastion-sg"
  description = "Security group for PharmaFlow Bastion host"
  vpc_id      = aws_vpc.pharmaflow.id

  tags = {
    Name        = "pharmaflow-bastion-sg"
    Project     = "PharmaFlow"
    Environment = "prod"
  }
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  security_group_id = aws_security_group.bastion.id

  cidr_ipv4   = var.admin_cidr
  from_port   = 22
  ip_protocol = "tcp"
  to_port     = 22
}

resource "aws_vpc_security_group_egress_rule" "bastion_all" {
  security_group_id = aws_security_group.bastion.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

# ---------------------------------------------------------
# Public ALB Security Group
# ---------------------------------------------------------

resource "aws_security_group" "public_alb" {
  name        = "pharmaflow-public-alb-sg"
  description = "Security group for PharmaFlow Public ALB"
  vpc_id      = aws_vpc.pharmaflow.id

  tags = {
    Name        = "pharmaflow-public-alb-sg"
    Project     = "PharmaFlow"
    Environment = "prod"
  }
}

resource "aws_vpc_security_group_ingress_rule" "public_alb_http" {
  security_group_id = aws_security_group.public_alb.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 80
  ip_protocol = "tcp"
  to_port     = 80
}

resource "aws_vpc_security_group_egress_rule" "public_alb_all" {
  security_group_id = aws_security_group.public_alb.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

# ---------------------------------------------------------
# Nginx Security Group
# ---------------------------------------------------------

resource "aws_security_group" "nginx" {
  name        = "pharmaflow-nginx-sg"
  description = "Security group for PharmaFlow Nginx servers"
  vpc_id      = aws_vpc.pharmaflow.id

  tags = {
    Name        = "pharmaflow-nginx-sg"
    Project     = "PharmaFlow"
    Environment = "prod"
  }
}

resource "aws_vpc_security_group_ingress_rule" "nginx_http" {
  security_group_id            = aws_security_group.nginx.id
  referenced_security_group_id = aws_security_group.public_alb.id

  from_port   = 80
  ip_protocol = "tcp"
  to_port     = 80
}

resource "aws_vpc_security_group_ingress_rule" "nginx_ssh" {
  security_group_id            = aws_security_group.nginx.id
  referenced_security_group_id = aws_security_group.bastion.id

  from_port   = 22
  ip_protocol = "tcp"
  to_port     = 22
}

resource "aws_vpc_security_group_egress_rule" "nginx_all" {
  security_group_id = aws_security_group.nginx.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

# ---------------------------------------------------------
# Internal ALB Security Group
# ---------------------------------------------------------

resource "aws_security_group" "internal_alb" {
  name        = "pharmaflow-internal-alb-sg"
  description = "Security group for PharmaFlow Internal ALB"
  vpc_id      = aws_vpc.pharmaflow.id

  tags = {
    Name        = "pharmaflow-internal-alb-sg"
    Project     = "PharmaFlow"
    Environment = "prod"
  }
}

resource "aws_vpc_security_group_ingress_rule" "internal_alb_from_nginx" {
  security_group_id            = aws_security_group.internal_alb.id
  referenced_security_group_id = aws_security_group.nginx.id

  from_port   = 80
  ip_protocol = "tcp"
  to_port     = 80
}

resource "aws_vpc_security_group_egress_rule" "internal_alb_all" {
  security_group_id = aws_security_group.internal_alb.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

# ---------------------------------------------------------
# Django Security Group
# ---------------------------------------------------------

resource "aws_security_group" "django" {
  name        = "pharmaflow-django-sg"
  description = "Security group for PharmaFlow Django servers"
  vpc_id      = aws_vpc.pharmaflow.id

  tags = {
    Name        = "pharmaflow-django-sg"
    Project     = "PharmaFlow"
    Environment = "prod"
  }
}

resource "aws_vpc_security_group_ingress_rule" "django_app" {
  security_group_id            = aws_security_group.django.id
  referenced_security_group_id = aws_security_group.internal_alb.id

  from_port   = 8000
  ip_protocol = "tcp"
  to_port     = 8000
}

resource "aws_vpc_security_group_ingress_rule" "django_ssh" {
  security_group_id            = aws_security_group.django.id
  referenced_security_group_id = aws_security_group.bastion.id

  from_port   = 22
  ip_protocol = "tcp"
  to_port     = 22
}

resource "aws_vpc_security_group_egress_rule" "django_all" {
  security_group_id = aws_security_group.django.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

# ---------------------------------------------------------
# RDS Security Group
# ---------------------------------------------------------

resource "aws_security_group" "rds" {
  name        = "pharmaflow-rds-sg"
  description = "Security group for PharmaFlow RDS"
  vpc_id      = aws_vpc.pharmaflow.id

  tags = {
    Name        = "pharmaflow-rds-sg"
    Project     = "PharmaFlow"
    Environment = "prod"
  }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_django" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.django.id

  from_port   = 3306
  ip_protocol = "tcp"
  to_port     = 3306
}

resource "aws_vpc_security_group_egress_rule" "rds_all" {
  security_group_id = aws_security_group.rds.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

# ---------------------------------------------------------
# EFS Security Group
# ---------------------------------------------------------

resource "aws_security_group" "efs" {
  name        = "pharmaflow-efs-sg"
  description = "Security group for PharmaFlow EFS"
  vpc_id      = aws_vpc.pharmaflow.id

  tags = {
    Name        = "pharmaflow-efs-sg"
    Project     = "PharmaFlow"
    Environment = "prod"
  }
}

resource "aws_vpc_security_group_ingress_rule" "efs_from_django" {
  security_group_id            = aws_security_group.efs.id
  referenced_security_group_id = aws_security_group.django.id

  from_port   = 2049
  ip_protocol = "tcp"
  to_port     = 2049
}

resource "aws_vpc_security_group_ingress_rule" "efs_from_nginx" {
  security_group_id            = aws_security_group.efs.id
  referenced_security_group_id = aws_security_group.nginx.id

  from_port   = 2049
  ip_protocol = "tcp"
  to_port     = 2049
}

resource "aws_vpc_security_group_egress_rule" "efs_all" {
  security_group_id = aws_security_group.efs.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

