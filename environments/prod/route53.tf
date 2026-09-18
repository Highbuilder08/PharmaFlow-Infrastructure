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
# Route53 Application Alias
# ---------------------------------------------------------
#
# The application alias is now owned by the EKS ingress path rather than
# the legacy public ALB. Keep the existing Route53 record in AWS while
# removing it from this Terraform state to prevent a future apply from
# redirecting pharmaflow.homes back to the legacy ALB.
#
removed {
  from = aws_route53_record.public_alb

  lifecycle {
    destroy = false
  }
}
