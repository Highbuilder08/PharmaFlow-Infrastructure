# ---------------------------------------------------------
# PharmaFlow ElastiCache for Valkey
#
# Purpose:
# - Shared Django application cache
# - Multi-AZ managed cache outside the EKS worker capacity
# - Accessible only from the EKS cluster security group
# ---------------------------------------------------------

resource "aws_elasticache_subnet_group" "pharmaflow" {
  name = "pharmaflow-valkey-subnet-group"

  subnet_ids = [
    aws_subnet.db_private_a.id,
    aws_subnet.db_private_c.id
  ]

  tags = {
    Name        = "pharmaflow-valkey-subnet-group"
    Project     = "PharmaFlow"
    Environment = "prod"
    ManagedBy   = "Terraform"
  }
}

resource "aws_security_group" "valkey" {
  name        = "pharmaflow-valkey-sg"
  description = "Security group for PharmaFlow ElastiCache Valkey"
  vpc_id      = aws_vpc.pharmaflow.id

  tags = {
    Name        = "pharmaflow-valkey-sg"
    Project     = "PharmaFlow"
    Environment = "prod"
    ManagedBy   = "Terraform"
  }
}

resource "aws_vpc_security_group_ingress_rule" "valkey_from_eks" {
  security_group_id = aws_security_group.valkey.id

  referenced_security_group_id = (
    aws_eks_cluster.pharmaflow.vpc_config[0].cluster_security_group_id
  )

  from_port   = 6379
  to_port     = 6379
  ip_protocol = "tcp"

  description = "Allow Valkey access from PharmaFlow EKS"
}

resource "aws_vpc_security_group_egress_rule" "valkey_all" {
  security_group_id = aws_security_group.valkey.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

resource "aws_elasticache_replication_group" "pharmaflow" {
  replication_group_id = "pharmaflow-valkey"
  description          = "PharmaFlow managed Valkey cache"

  engine         = "valkey"
  engine_version = "8.0"
  node_type      = "cache.t4g.micro"

  port = 6379

  parameter_group_name = "default.valkey8"

  subnet_group_name = aws_elasticache_subnet_group.pharmaflow.name

  security_group_ids = [
    aws_security_group.valkey.id
  ]

  num_cache_clusters = 2

  automatic_failover_enabled = true
  multi_az_enabled           = true

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  apply_immediately = true

  tags = {
    Name        = "pharmaflow-valkey"
    Project     = "PharmaFlow"
    Environment = "prod"
    ManagedBy   = "Terraform"
  }
}
