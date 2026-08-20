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

