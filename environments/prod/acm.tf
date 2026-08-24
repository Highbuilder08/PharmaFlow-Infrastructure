# ---------------------------------------------------------
# ACM Certificate
# ---------------------------------------------------------

resource "aws_acm_certificate" "pharmaflow" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "pharmaflow-acm"
    Project     = "PharmaFlow"
    Environment = "prod"
  }
}

# ---------------------------------------------------------
# ACM DNS Validation Record
# ---------------------------------------------------------

resource "aws_route53_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.pharmaflow.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = aws_route53_zone.pharmaflow.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60

  records = [
    each.value.record
  ]
}

# ---------------------------------------------------------
# ACM Certificate Validation
# ---------------------------------------------------------

resource "aws_acm_certificate_validation" "pharmaflow" {
  certificate_arn = aws_acm_certificate.pharmaflow.arn

  validation_record_fqdns = [
    for record in aws_route53_record.acm_validation :
    record.fqdn
  ]
}

