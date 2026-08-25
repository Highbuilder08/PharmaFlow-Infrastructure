# ---------------------------------------------------------
# SNS Topic for CloudWatch Alarms
# ---------------------------------------------------------

resource "aws_sns_topic" "cloudwatch_alerts" {
  name = "pharmaflow-cloudwatch-alerts"

  tags = {
    Name        = "pharmaflow-cloudwatch-alerts"
    Project     = "PharmaFlow"
    Environment = "prod"
  }
}

# ---------------------------------------------------------
# Email Subscription
# ---------------------------------------------------------

resource "aws_sns_topic_subscription" "cloudwatch_email" {
  topic_arn = aws_sns_topic.cloudwatch_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

