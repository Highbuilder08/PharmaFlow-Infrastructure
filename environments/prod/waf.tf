# ---------------------------------------------------------
# AWS WAF Web ACL
# Public ALB Protection
# ---------------------------------------------------------

resource "aws_wafv2_web_acl" "public" {
  name        = "pharmaflow-public-waf"
  description = "WAF for PharmaFlow Public ALB"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # -------------------------------------------------------
  # AWS Managed Rules - Common Rule Set
  # -------------------------------------------------------

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # -------------------------------------------------------
  # AWS Managed Rules - Known Bad Inputs
  # -------------------------------------------------------

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 20

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesKnownBadInputsRuleSet"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "pharmaflow-public-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name        = "pharmaflow-public-waf"
    Project     = "PharmaFlow"
    Environment = "prod"
  }
}

# ---------------------------------------------------------
# WAF -> Public ALB Association
# ---------------------------------------------------------

resource "aws_wafv2_web_acl_association" "public_alb" {
  resource_arn = aws_lb.public.arn
  web_acl_arn  = aws_wafv2_web_acl.public.arn
}

