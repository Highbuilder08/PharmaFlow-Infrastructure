# ---------------------------------------------------------
# Amazon SES - Easy DKIM
# ---------------------------------------------------------

resource "aws_route53_record" "ses_dkim" {
  count = 3

  zone_id = aws_route53_zone.pharmaflow.zone_id
  name    = "${aws_sesv2_email_identity.pharmaflow.dkim_signing_attributes[0].tokens[count.index]}._domainkey.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300

  records = [
    "${aws_sesv2_email_identity.pharmaflow.dkim_signing_attributes[0].tokens[count.index]}.dkim.amazonses.com"
  ]
}

# ---------------------------------------------------------
# DMARC
# 초기 운영 단계에서는 모니터링 정책(p=none)
# ---------------------------------------------------------

resource "aws_route53_record" "dmarc" {
  zone_id = aws_route53_zone.pharmaflow.zone_id
  name    = "_dmarc.${var.domain_name}"
  type    = "TXT"
  ttl     = 300

  records = [
    "v=DMARC1; p=none;"
  ]
}

# ---------------------------------------------------------
# Amazon SES - Custom MAIL FROM DNS
# ---------------------------------------------------------

resource "aws_route53_record" "ses_mail_from_mx" {
  zone_id = aws_route53_zone.pharmaflow.zone_id
  name    = "mail.${var.domain_name}"
  type    = "MX"
  ttl     = 300

  records = [
    "10 feedback-smtp.ap-northeast-2.amazonses.com"
  ]
}

resource "aws_route53_record" "ses_mail_from_spf" {
  zone_id = aws_route53_zone.pharmaflow.zone_id
  name    = "mail.${var.domain_name}"
  type    = "TXT"
  ttl     = 300

  records = [
    "v=spf1 include:amazonses.com ~all"
  ]
}
