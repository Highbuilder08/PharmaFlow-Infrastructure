# ============================================================
# PharmaFlow ECR Repositories
# ============================================================

resource "aws_ecr_repository" "django" {
  name                 = "pharmaflow-django"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name        = "pharmaflow-django"
    Project     = "PharmaFlow"
    Environment = "prod"
  }
}

resource "aws_ecr_repository" "nginx" {
  name                 = "pharmaflow-nginx"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name        = "pharmaflow-nginx"
    Project     = "PharmaFlow"
    Environment = "prod"
  }
}
