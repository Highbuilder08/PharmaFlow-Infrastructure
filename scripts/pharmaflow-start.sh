#!/bin/bash
set -e

echo "=== PharmaFlow 업무 시작 ==="

# 1. RDS 시작
echo "[1/5] RDS 시작"

RDS_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier pharmaflow-db \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text)

if [ "$RDS_STATUS" = "stopped" ]; then
  aws rds start-db-instance \
    --db-instance-identifier pharmaflow-db
fi

echo "[2/5] RDS available 대기"

aws rds wait db-instance-available \
  --db-instance-identifier pharmaflow-db

echo "RDS 준비 완료"

# 2. Django Base EC2 시작
echo "[3/5] Django Base EC2 시작"

DJANGO_BASE_ID=$(aws ec2 describe-instances \
  --filters \
    "Name=tag:Name,Values=pharmaflow-django-base" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

if [ "$DJANGO_BASE_ID" != "None" ]; then
  aws ec2 start-instances \
    --instance-ids "$DJANGO_BASE_ID" >/dev/null
fi

# 3. Nginx Base EC2 시작
echo "[4/5] Nginx Base EC2 시작"

NGINX_ID=$(aws ec2 describe-instances \
  --filters \
    "Name=tag:Name,Values=pharmaflow-nginx" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

if [ "$NGINX_ID" != "None" ]; then
  aws ec2 start-instances \
    --instance-ids "$NGINX_ID" >/dev/null
fi

# 4. Django ASG 시작
echo "[5/5] Django ASG 시작"

aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name pharmaflow-django-asg \
  --min-size 0 \
  --desired-capacity 2

echo "=== PharmaFlow 업무 시작 요청 완료 ==="
