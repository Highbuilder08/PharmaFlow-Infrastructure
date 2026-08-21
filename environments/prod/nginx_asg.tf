# ---------------------------------------------------------
# Nginx Target Group
# Public ALB -> Nginx ASG
# ---------------------------------------------------------

resource "aws_lb_target_group" "nginx" {
  name        = "pharmaflow-nginx-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.pharmaflow.id
  target_type = "instance"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-399"
  }

  tags = {
    Name        = "pharmaflow-nginx-tg"
    Project     = "PharmaFlow"
    Environment = "prod"
    Role        = "nginx"
  }
}


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

  target_group_arns = [
    aws_lb_target_group.nginx.arn
  ]

  health_check_type         = "ELB"
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
