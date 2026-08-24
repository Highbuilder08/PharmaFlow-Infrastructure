# ---------------------------------------------------------
# Public Application Load Balancer
# Internet -> Public ALB -> Nginx ASG
# ---------------------------------------------------------

resource "aws_lb" "public" {
  name               = "pharmaflow-public-alb"
  internal           = false
  load_balancer_type = "application"

  security_groups = [
    aws_security_group.public_alb.id
  ]

  subnets = [
    aws_subnet.public_a.id,
    aws_subnet.public_c.id
  ]

  tags = {
    Name        = "pharmaflow-public-alb"
    Project     = "PharmaFlow"
    Environment = "prod"
    Tier        = "web"
  }
}

# ---------------------------------------------------------
# Public ALB HTTP Listener
# Public ALB :80 -> Nginx Target Group
# ---------------------------------------------------------

resource "aws_lb_listener" "public_http" {
  load_balancer_arn = aws_lb.public.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# ---------------------------------------------------------
# Public ALB HTTPS Listener
# HTTPS :443 -> Nginx Target Group
# ---------------------------------------------------------

resource "aws_lb_listener" "public_https" {
  load_balancer_arn = aws_lb.public.arn
  port              = 443
  protocol          = "HTTPS"

  certificate_arn = aws_acm_certificate_validation.pharmaflow.certificate_arn
  ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nginx.arn
  }
}
