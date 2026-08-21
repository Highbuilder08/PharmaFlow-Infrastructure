#!/bin/bash
set -e

export AWS_PAGER=""

echo "=== PharmaFlow 업무 시작 ==="

# 1. NAT 시작
echo "[1/7] NAT EC2 시작"

NAT_ID=$(aws ec2 describe-instances \
  --filters \
    "Name=tag:Name,Values=pharmaflow-nat" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

if [ "$NAT_ID" != "None" ] && [ -n "$NAT_ID" ]; then
  aws ec2 start-instances \
    --instance-ids "$NAT_ID" \
    >/dev/null
fi

# 2. Bastion 시작
echo "[2/7] Bastion EC2 시작"

BASTION_ID=$(aws ec2 describe-instances \
  --filters \
    "Name=tag:Name,Values=pharmaflow-bastion" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

if [ "$BASTION_ID" != "None" ] && [ -n "$BASTION_ID" ]; then
  aws ec2 start-instances \
    --instance-ids "$BASTION_ID" \
    >/dev/null
fi

# 3. RDS 시작
echo "[3/7] RDS 시작"

RDS_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier pharmaflow-db \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text)

echo "현재 RDS 상태: $RDS_STATUS"

if [ "$RDS_STATUS" = "stopped" ]; then
  aws rds start-db-instance \
    --db-instance-identifier pharmaflow-db \
    >/dev/null
fi

echo "[4/7] RDS available 대기"

while true; do
  RDS_STATUS=$(aws rds describe-db-instances \
    --db-instance-identifier pharmaflow-db \
    --query 'DBInstances[0].DBInstanceStatus' \
    --output text)

  echo "현재 RDS 상태: $RDS_STATUS"

  if [ "$RDS_STATUS" = "available" ]; then
    break
  fi

  sleep 10
done

echo "RDS 준비 완료"

# 5. Django Base 시작
echo "[5/7] Django Base EC2 시작"

DJANGO_BASE_ID=$(aws ec2 describe-instances \
  --filters \
    "Name=tag:Name,Values=pharmaflow-django-base" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

if [ "$DJANGO_BASE_ID" != "None" ] && [ -n "$DJANGO_BASE_ID" ]; then
  aws ec2 start-instances \
    --instance-ids "$DJANGO_BASE_ID" \
    >/dev/null
fi

# 6. Nginx Base 시작
echo "[6/7] Nginx Base EC2 시작"

NGINX_ID=$(aws ec2 describe-instances \
  --filters \
    "Name=tag:Name,Values=pharmaflow-nginx" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

if [ "$NGINX_ID" != "None" ] && [ -n "$NGINX_ID" ]; then
  aws ec2 start-instances \
    --instance-ids "$NGINX_ID" \
    >/dev/null
fi

# 7. Django ASG 시작
echo "[7/7] Django ASG 시작"

aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name pharmaflow-django-asg \
  --min-size 0 \
  --desired-capacity 2

echo "=== PharmaFlow 업무 시작 요청 완료 ==="

