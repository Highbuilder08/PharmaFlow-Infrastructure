# ---------------------------------------------------------
# Django Golden AMI
# ---------------------------------------------------------

resource "aws_ami_from_instance" "django_golden" {
  name               = "pharmaflow-django-golden"
  source_instance_id = aws_instance.django_base.id

  snapshot_without_reboot = false

  tags = {
    Name        = "pharmaflow-django-golden"
    Project     = "PharmaFlow"
    Environment = "prod"
    Role        = "django"
  }
}

# ---------------------------------------------------------
# Django Golden AMI v2
# ASG 대응: DJANGO_ALLOWED_HOSTS=* 반영
# ---------------------------------------------------------

resource "aws_ami_from_instance" "django_golden_v2" {
  name               = "pharmaflow-django-golden-v2"
  source_instance_id = aws_instance.django_base.id

  snapshot_without_reboot = false

  tags = {
    Name        = "pharmaflow-django-golden-v2"
    Project     = "PharmaFlow"
    Environment = "prod"
    Role        = "django"
    Version     = "v2"
  }
}


# ---------------------------------------------------------
# Nginx Golden AMI
# ---------------------------------------------------------

resource "aws_ami_from_instance" "nginx_golden" {
  name               = "pharmaflow-nginx-golden"
  source_instance_id = aws_instance.nginx.id

  snapshot_without_reboot = false

  tags = {
    Name        = "pharmaflow-nginx-golden"
    Project     = "PharmaFlow"
    Environment = "prod"
    Role        = "nginx"
  }
}

# ---------------------------------------------------------
# Nginx Golden AMI v2
# Internal ALB backend configuration
# ---------------------------------------------------------

resource "aws_ami_from_instance" "nginx_golden_v2" {
  name               = "pharmaflow-nginx-golden-v2"
  source_instance_id = aws_instance.nginx.id

  snapshot_without_reboot = false

  tags = {
    Name        = "pharmaflow-nginx-golden-v2"
    Project     = "PharmaFlow"
    Environment = "prod"
    Role        = "nginx"
    Version     = "v2"
  }
}


# ---------------------------------------------------------
# Django Golden AMI v3
# 3-Tier DB endpoint + ASG configuration
# ---------------------------------------------------------

resource "aws_ami_from_instance" "django_golden_v3" {
  name               = "pharmaflow-django-golden-v3"
  source_instance_id = aws_instance.django_base.id

  snapshot_without_reboot = false

  tags = {
    Name        = "pharmaflow-django-golden-v3"
    Project     = "PharmaFlow"
    Environment = "prod"
    Role        = "django"
    Version     = "v3"
  }
}

# ---------------------------------------------------------
# Django Golden AMI v4
# Health Check endpoints included
# ---------------------------------------------------------

resource "aws_ami_from_instance" "django_golden_v4" {
  name               = "pharmaflow-django-golden-v4"
  source_instance_id = aws_instance.django_base.id

  snapshot_without_reboot = false

  tags = {
    Name        = "pharmaflow-django-golden-v4"
    Project     = "PharmaFlow"
    Environment = "prod"
    Role        = "django"
    Version     = "v4"
  }
}

# ---------------------------------------------------------
# Django Golden AMI v5
# Shared Static EFS configuration
# ---------------------------------------------------------

resource "aws_ami_from_instance" "django_golden_v5" {
  name               = "pharmaflow-django-golden-v5"
  source_instance_id = aws_instance.django_base.id

  snapshot_without_reboot = false

  tags = {
    Name        = "pharmaflow-django-golden-v5"
    Project     = "PharmaFlow"
    Environment = "prod"
    Role        = "django"
    Version     = "v5"
  }
}

# ---------------------------------------------------------
# Nginx Golden AMI v3
# Shared Static EFS + /static/ configuration
# ---------------------------------------------------------

resource "aws_ami_from_instance" "nginx_golden_v3" {
  name               = "pharmaflow-nginx-golden-v3"
  source_instance_id = aws_instance.nginx.id

  snapshot_without_reboot = false

  tags = {
    Name        = "pharmaflow-nginx-golden-v3"
    Project     = "PharmaFlow"
    Environment = "prod"
    Role        = "nginx"
    Version     = "v3"
  }
}
