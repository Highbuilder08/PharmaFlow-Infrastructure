# ---------------------------------------------------------
# Route53 Hosted Zone
# ---------------------------------------------------------

resource "aws_route53_zone" "pharmaflow" {
  name = var.domain_name

  tags = {
    Name        = "pharmaflow-hosted-zone"
    Project     = "PharmaFlow"
    Environment = "prod"
  }
}

# ---------------------------------------------------------
# Route53 Alias
# pharmaflow.homes -> Public ALB
# ---------------------------------------------------------

resource "aws_route53_record" "public_alb" {
  zone_id = aws_route53_zone.pharmaflow.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.public.dns_name
    zone_id                = aws_lb.public.zone_id
    evaluate_target_health = true
  }
}
