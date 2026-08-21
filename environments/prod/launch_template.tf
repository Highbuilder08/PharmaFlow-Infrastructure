# ---------------------------------------------------------
# Django Launch Template
# ---------------------------------------------------------

resource "aws_launch_template" "django" {
  name_prefix   = "pharmaflow-django-"
  image_id      = aws_ami_from_instance.django_golden_v3.id
  instance_type = "t3.small"
  key_name      = var.ec2_key_name

  vpc_security_group_ids = [
    aws_security_group.django.id
  ]

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name        = "pharmaflow-django-asg"
      Project     = "PharmaFlow"
      Environment = "prod"
      Role        = "django"
    }
  }

  tags = {
    Name        = "pharmaflow-django-lt"
    Project     = "PharmaFlow"
    Environment = "prod"
  }
}


# ---------------------------------------------------------
# Nginx Launch Template
# ---------------------------------------------------------

resource "aws_launch_template" "nginx" {
  name_prefix   = "pharmaflow-nginx-"
  image_id      = aws_ami_from_instance.nginx_golden.id
  instance_type = "t3.micro"
  key_name      = var.ec2_key_name

  vpc_security_group_ids = [
    aws_security_group.nginx.id
  ]

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name        = "pharmaflow-nginx-asg"
      Project     = "PharmaFlow"
      Environment = "prod"
      Role        = "nginx"
    }
  }

  tags = {
    Name        = "pharmaflow-nginx-lt"
    Project     = "PharmaFlow"
    Environment = "prod"
  }
}

