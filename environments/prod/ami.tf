# ---------------------------------------------------------
# Django Golden AMI v6
# Final EC2/ASG baseline
# - Health Check
# - Shared Static/Media EFS
# - Amazon SES SMTP configuration
# ---------------------------------------------------------

resource "aws_ami_from_instance" "django_golden_v6" {
  name               = "pharmaflow-django-golden-v6"
  source_instance_id = aws_instance.django_base.id

  snapshot_without_reboot = false

  tags = {
    Name        = "pharmaflow-django-golden-v6"
    Project     = "PharmaFlow"
    Environment = "prod"
    Role        = "django"
    Version     = "v6"
  }
}

# ---------------------------------------------------------
# Nginx Golden AMI v3
# Final EC2/ASG baseline
# - Internal ALB backend
# - Shared Static/Media EFS
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
