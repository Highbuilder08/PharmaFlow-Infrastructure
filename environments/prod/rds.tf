resource "aws_db_subnet_group" "pharmaflow" {
  name = "pharmaflow-db-subnet-group"

  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_c.id
  ]


  tags = {
    Name        = "pharmaflow-db-subnet-group"
    Project     = "PharmaFlow"
    Environment = "prod"
  }
}

resource "aws_db_instance" "pharmaflow" {
  identifier = "pharmaflow-db"

  engine = "mariadb"

  instance_class        = "db.t3.micro"
  allocated_storage     = 20
  max_allocated_storage = 50
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  port = 3306

  db_subnet_group_name   = aws_db_subnet_group.pharmaflow.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = false
  multi_az            = false

  backup_retention_period = 1

  skip_final_snapshot = true
  deletion_protection = false

  apply_immediately = true

  tags = {
    Name        = "pharmaflow-rds"
    Project     = "PharmaFlow"
    Environment = "prod"
    Role        = "database"
  }
}

# ---------------------------------------------------------
# 3-Tier Database Subnet Group
# ---------------------------------------------------------

resource "aws_db_subnet_group" "pharmaflow_db_tier" {
  name = "pharmaflow-db-tier-subnet-group"

  subnet_ids = [
    aws_subnet.db_private_a.id,
    aws_subnet.db_private_c.id
  ]

  tags = {
    Name        = "pharmaflow-db-tier-subnet-group"
    Project     = "PharmaFlow"
    Environment = "prod"
    Tier        = "database"
  }
}

# ---------------------------------------------------------
# 3-Tier Database RDS
# Restored from migration snapshot
# ---------------------------------------------------------

resource "aws_db_instance" "pharmaflow_db_tier" {
  identifier = "pharmaflow-db-tier"

  snapshot_identifier = "pharmaflow-before-db-tier-migration"

  instance_class        = "db.t3.micro"
  allocated_storage     = 20
  max_allocated_storage = 50
  storage_type          = "gp3"
  storage_encrypted     = true

  port = 3306

  db_subnet_group_name   = aws_db_subnet_group.pharmaflow_db_tier.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = false
  multi_az            = true

  backup_retention_period = 1

  skip_final_snapshot = true
  deletion_protection = false

  apply_immediately = true

  tags = {
    Name        = "pharmaflow-rds-db-tier"
    Project     = "PharmaFlow"
    Environment = "prod"
    Role        = "database"
    Tier        = "database"
  }
}
