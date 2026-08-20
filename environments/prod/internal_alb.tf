# ---------------------------------------------------------
# Internal Application Load Balancer
# Nginx -> Internal ALB -> Django
# ---------------------------------------------------------

resource "aws_lb" "internal" {
  name               = "pharmaflow-internal-alb"
  internal           = true
  load_balancer_type = "application"

  security_groups = [
    aws_security_group.internal_alb.id
  ]

  subnets = [
    aws_subnet.private_a.id,
    aws_subnet.private_c.id
  ]

  tags = {
    Name        = "pharmaflow-internal-alb"
    Project     = "PharmaFlow"
    Environment = "prod"
  }
}


# ---------------------------------------------------------
# Django Target Group
# ---------------------------------------------------------

resource "aws_lb_target_group" "django" {
  name        = "pharmaflow-django-tg"
  port        = 8000
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.pharmaflow.id

  health_check {
    enabled             = true
    protocol            = "HTTP"
    port                = "traffic-port"
    path                = "/"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name        = "pharmaflow-django-tg"
    Project     = "PharmaFlow"
    Environment = "prod"
  }
}


# ---------------------------------------------------------
# Django Base EC2 Target Registration
# ---------------------------------------------------------

resource "aws_lb_target_group_attachment" "django_base" {
  target_group_arn = aws_lb_target_group.django.arn
  target_id        = aws_instance.django_base.id
  port             = 8000
}


# ---------------------------------------------------------
# Internal ALB HTTP Listener
# ---------------------------------------------------------

resource "aws_lb_listener" "internal_http" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.django.arn
  }
}

