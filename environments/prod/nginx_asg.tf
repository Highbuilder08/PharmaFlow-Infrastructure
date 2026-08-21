# ---------------------------------------------------------
# Nginx Auto Scaling Group
# Web Private Subnet A/C
# ---------------------------------------------------------

resource "aws_autoscaling_group" "nginx" {
  name = "pharmaflow-nginx-asg"

  min_size         = 0
  max_size         = 4
  desired_capacity = 2

  vpc_zone_identifier = [
    aws_subnet.web_private_a.id,
    aws_subnet.web_private_c.id
  ]

  health_check_type         = "EC2"
  health_check_grace_period = 180

  launch_template {
    id      = aws_launch_template.nginx.id
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
    value               = "pharmaflow-nginx-asg"
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
    value               = "nginx"
    propagate_at_launch = true
  }

  lifecycle {
    ignore_changes = [
      desired_capacity
    ]
  }
}
