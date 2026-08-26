# ---------------------------------------------------------
# Amazon SES - PharmaFlow Domain Identity
# ---------------------------------------------------------

resource "aws_sesv2_email_identity" "pharmaflow" {
  email_identity = var.domain_name

  dkim_signing_attributes {
    next_signing_key_length = "RSA_2048_BIT"
  }

  tags = {
    Name        = "pharmaflow-ses-domain"
    Project     = "PharmaFlow"
    Environment = "prod"
  }
}

# ---------------------------------------------------------
# Amazon SES - Custom MAIL FROM
# ---------------------------------------------------------

resource "aws_sesv2_email_identity_mail_from_attributes" "pharmaflow" {
  email_identity = aws_sesv2_email_identity.pharmaflow.email_identity

  mail_from_domain       = "mail.${var.domain_name}"
  behavior_on_mx_failure = "USE_DEFAULT_VALUE"
}
