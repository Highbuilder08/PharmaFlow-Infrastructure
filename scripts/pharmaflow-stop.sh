#!/bin/bash
set -e

export AWS_PAGER=""

echo "=== PharmaFlow 업무 종료 ==="

# 1. Django ASG 종료
echo "[1/7] Django ASG 축소"

aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name pharmaflow-django-asg \
  --min-size 0 \
  --desired-capacity 0

# 2. Django Base 중지
echo "[2/7] Django Base EC2 중지"

DJANGO_BASE_ID=$(aws ec2 describe-instances \
  --filters \
    "Name=tag:Name,Values=pharmaflow-django-base" \
    "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

if [ "$DJANGO_BASE_ID" != "None" ] && [ -n "$DJANGO_BASE_ID" ]; then
  aws ec2 stop-instances \
    --instance-ids "$DJANGO_BASE_ID" \
    >/dev/null
fi

# 3. Nginx Base 중지
echo "[3/7] Nginx Base EC2 중지"

NGINX_ID=$(aws ec2 describe-instances \
  --filters \
    "Name=tag:Name,Values=pharmaflow-nginx" \
    "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

if [ "$NGINX_ID" != "None" ] && [ -n "$NGINX_ID" ]; then
  aws ec2 stop-instances \
    --instance-ids "$NGINX_ID" \
    >/dev/null
fi

# 4. RDS 중지
echo "[4/7] RDS 중지"

RDS_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier pharmaflow-db \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text)

echo "현재 RDS 상태: $RDS_STATUS"

if [ "$RDS_STATUS" = "available" ]; then
  aws rds stop-db-instance \
    --db-instance-identifier pharmaflow-db \
    >/dev/null
fi

echo "[5/7] RDS stopped 대기"

while true; do
  RDS_STATUS=$(aws rds describe-db-instances \
    --db-instance-identifier pharmaflow-db \
    --query 'DBInstances[0].DBInstanceStatus' \
    --output text)

  echo "현재 RDS 상태: $RDS_STATUS"

  if [ "$RDS_STATUS" = "stopped" ]; then
    break
  fi

  sleep 10
done

# 6. Bastion 중지
echo "[6/7] Bastion EC2 중지"

BASTION_ID=$(aws ec2 describe-instances \
  --filters \
    "Name=tag:Name,Values=pharmaflow-bastion" \
    "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

if [ "$BASTION_ID" != "None" ] && [ -n "$BASTION_ID" ]; then
  aws ec2 stop-instances \
    --instance-ids "$BASTION_ID" \
    >/dev/null
fi

# 7. NAT 중지
echo "[7/7] NAT EC2 중지"

NAT_ID=$(aws ec2 describe-instances \
  --filters \
    "Name=tag:Name,Values=pharmaflow-nat" \
    "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

if [ "$NAT_ID" != "None" ] && [ -n "$NAT_ID" ]; then
  aws ec2 stop-instances \
    --instance-ids "$NAT_ID" \
    >/dev/null
fi

echo "=== PharmaFlow 업무 종료 완료 ==="

