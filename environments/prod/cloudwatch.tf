# ---------------------------------------------------------
# CloudWatch Alarms
# ---------------------------------------------------------

# ---------------------------------------------------------
# Nginx Target Group Healthy Host Count
# ---------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "nginx_tg_healthy_hosts" {
  alarm_name          = "pharmaflow-nginx-tg-healthy-hosts"
  alarm_description   = "Alarm when Nginx target group has fewer than 2 healthy targets"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  threshold           = 2

  metric_name = "HealthyHostCount"
  namespace   = "AWS/ApplicationELB"
  period      = 60
  statistic   = "Minimum"

  dimensions = {
    TargetGroup  = aws_lb_target_group.nginx.arn_suffix
    LoadBalancer = aws_lb.public.arn_suffix
  }

  treat_missing_data = "breaching"

  alarm_actions = [aws_sns_topic.cloudwatch_alerts.arn]
  ok_actions    = [aws_sns_topic.cloudwatch_alerts.arn]

  tags = {
    Name        = "pharmaflow-nginx-tg-healthy-hosts"
    Project     = "PharmaFlow"
    Environment = "prod"
  }
}

# ---------------------------------------------------------
# Django Target Group Healthy Host Count
# ---------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "django_tg_healthy_hosts" {
  alarm_name          = "pharmaflow-django-tg-healthy-hosts"
  alarm_description   = "Alarm when Django target group has fewer than 2 healthy targets"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  threshold           = 2

  metric_name = "HealthyHostCount"
  namespace   = "AWS/ApplicationELB"
  period      = 60
  statistic   = "Minimum"

  dimensions = {
    TargetGroup  = aws_lb_target_group.django.arn_suffix
    LoadBalancer = aws_lb.internal.arn_suffix
  }

  treat_missing_data = "breaching"

  alarm_actions = [aws_sns_topic.cloudwatch_alerts.arn]
  ok_actions    = [aws_sns_topic.cloudwatch_alerts.arn]

  tags = {
    Name        = "pharmaflow-django-tg-healthy-hosts"
    Project     = "PharmaFlow"
    Environment = "prod"
  }
}

# ---------------------------------------------------------
# RDS CPU Utilization
# ---------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  alarm_name          = "pharmaflow-rds-cpu-high"
  alarm_description   = "Alarm when DB tier RDS CPU utilization exceeds 80 percent"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  threshold           = 80

  metric_name = "CPUUtilization"
  namespace   = "AWS/RDS"
  period      = 60
  statistic   = "Average"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.pharmaflow_db_tier.identifier
  }

  treat_missing_data = "missing"

  alarm_actions = [aws_sns_topic.cloudwatch_alerts.arn]
  ok_actions    = [aws_sns_topic.cloudwatch_alerts.arn]

  tags = {
    Name        = "pharmaflow-rds-cpu-high"
    Project     = "PharmaFlow"
    Environment = "prod"
  }
}

# ---------------------------------------------------------
# Public ALB Target 5XX
# ---------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "public_alb_target_5xx" {
  alarm_name          = "pharmaflow-public-alb-target-5xx"
  alarm_description   = "Alarm when Public ALB target responses include 5XX errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0

  metric_name = "HTTPCode_Target_5XX_Count"
  namespace   = "AWS/ApplicationELB"
  period      = 60
  statistic   = "Sum"

  dimensions = {
    LoadBalancer = aws_lb.public.arn_suffix
  }

  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.cloudwatch_alerts.arn]
  ok_actions    = [aws_sns_topic.cloudwatch_alerts.arn]

  tags = {
    Name        = "pharmaflow-public-alb-target-5xx"
    Project     = "PharmaFlow"
    Environment = "prod"
  }
}

