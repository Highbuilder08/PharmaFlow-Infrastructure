# ---------------------------------------------------------
# Django Auto Scaling Group
# Internal ALB -> Django ASG
# ---------------------------------------------------------

resource "aws_autoscaling_group" "django" {
  name = "pharmaflow-django-asg"

  min_size         = 0
  max_size         = 4
  desired_capacity = 2

  vpc_zone_identifier = [
    aws_subnet.private_a.id,
    aws_subnet.private_c.id
  ]

  target_group_arns = [
    aws_lb_target_group.django.arn
  ]

  health_check_type         = "ELB"
  health_check_grace_period = 180

  launch_template {
    id      = aws_launch_template.django.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 180
    }
  }

  tag {
    key                 = "Name"
    value               = "pharmaflow-django-asg"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = "PharmaFlow"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = "prod"
    propagate_at_launch = true
  }

  tag {
    key                 = "Role"
    value               = "django"
    propagate_at_launch = true
  }

  lifecycle {
    ignore_changes = [
      desired_capacity
    ]
  }
}



