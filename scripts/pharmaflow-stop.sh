#!/bin/bash
set -e

echo "=== PharmaFlow 업무 종료 ==="

# 1. Django ASG 종료
echo "[1/5] Django ASG 축소"
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name pharmaflow-django-asg \
  --min-size 0 \
  --desired-capacity 0

# 2. Django Base EC2 중지
echo "[2/5] Django Base EC2 중지"
DJANGO_BASE_ID=$(aws ec2 describe-instances \
  --filters \
    "Name=tag:Name,Values=pharmaflow-django-base" \
    "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

if [ "$DJANGO_BASE_ID" != "None" ]; then
  aws ec2 stop-instances --instance-ids "$DJANGO_BASE_ID"
fi

# 3. Nginx Base EC2 중지
echo "[3/5] Nginx Base EC2 중지"
NGINX_ID=$(aws ec2 describe-instances \
  --filters \
    "Name=tag:Name,Values=pharmaflow-nginx" \
    "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

if [ "$NGINX_ID" != "None" ]; then
  aws ec2 stop-instances --instance-ids "$NGINX_ID"
fi

# 4. RDS 중지
echo "[4/5] RDS 중지"
RDS_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier pharmaflow-db \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text)

if [ "$RDS_STATUS" = "available" ]; then
  aws rds stop-db-instance \
    --db-instance-identifier pharmaflow-db
fi

echo "[5/5] RDS stopped 대기"

aws rds wait db-instance-stopped \
  --db-instance-identifier pharmaflow-db

echo "=== PharmaFlow 업무 종료 완료 ==="
