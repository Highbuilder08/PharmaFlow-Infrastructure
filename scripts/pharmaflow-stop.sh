#!/bin/bash
set -e

export AWS_PAGER=""

echo "=== PharmaFlow 업무 종료 ==="

# ---------------------------------------------------------
# 리소스 ID 조회
# ---------------------------------------------------------

DJANGO_BASE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=pharmaflow-django-base" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

NGINX_BASE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=pharmaflow-nginx" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

BASTION_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=pharmaflow-bastion" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

NAT_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=pharmaflow-nat" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

EC2_IDS=""

for INSTANCE_ID in \
  "$DJANGO_BASE_ID" \
  "$NGINX_BASE_ID" \
  "$BASTION_ID" \
  "$NAT_ID"
do
  if [ "$INSTANCE_ID" != "None" ] && [ -n "$INSTANCE_ID" ]; then
    EC2_IDS="$EC2_IDS $INSTANCE_ID"
  fi
done

# ---------------------------------------------------------
# 1. ASG desired capacity 0 적용
# ---------------------------------------------------------

echo "[1/3] Django / Nginx ASG 축소 요청"

aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name pharmaflow-django-asg \
  --min-size 0 \
  --desired-capacity 0

aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name pharmaflow-nginx-asg \
  --min-size 0 \
  --desired-capacity 0

echo "ASG desired capacity 0 적용 요청 완료"

# ---------------------------------------------------------
# 2. EC2 / RDS 전체 중지 요청
# ---------------------------------------------------------

echo "[2/3] EC2 / RDS 전체 중지 요청"

if [ -n "$EC2_IDS" ]; then
  aws ec2 stop-instances \
    --instance-ids $EC2_IDS \
    >/dev/null
fi

DB_TIER_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier pharmaflow-db-tier \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text)

if [ "$DB_TIER_STATUS" = "available" ]; then
  aws rds stop-db-instance \
    --db-instance-identifier pharmaflow-db-tier \
    >/dev/null
fi

LEGACY_DB_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier pharmaflow-db \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text)

if [ "$LEGACY_DB_STATUS" = "available" ]; then
  aws rds stop-db-instance \
    --db-instance-identifier pharmaflow-db \
    >/dev/null
fi

echo "EC2 / RDS 중지 요청 완료"

# ---------------------------------------------------------
# 3. 종료 요청 반영 확인
# ---------------------------------------------------------

echo "[3/3] 종료 요청 반영 확인"

while true; do
  DJANGO_DESIRED=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names pharmaflow-django-asg \
    --query 'AutoScalingGroups[0].DesiredCapacity' \
    --output text)

  NGINX_DESIRED=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names pharmaflow-nginx-asg \
    --query 'AutoScalingGroups[0].DesiredCapacity' \
    --output text)

  EC2_STOPPING_OR_STOPPED=0

  if [ -n "$EC2_IDS" ]; then
    EC2_STOPPING_OR_STOPPED=$(aws ec2 describe-instances \
      --instance-ids $EC2_IDS \
      --query 'length(Reservations[].Instances[] | [?State.Name==`stopping` || State.Name==`stopped`])' \
      --output text)
  fi

  DB_TIER_STATUS=$(aws rds describe-db-instances \
    --db-instance-identifier pharmaflow-db-tier \
    --query 'DBInstances[0].DBInstanceStatus' \
    --output text)

  LEGACY_DB_STATUS=$(aws rds describe-db-instances \
    --db-instance-identifier pharmaflow-db \
    --query 'DBInstances[0].DBInstanceStatus' \
    --output text)

  echo "Django ASG desired : $DJANGO_DESIRED"
  echo "Nginx ASG desired  : $NGINX_DESIRED"
  echo "EC2 종료 진행 수    : $EC2_STOPPING_OR_STOPPED / 4"
  echo "DB Tier RDS        : $DB_TIER_STATUS"
  echo "Legacy RDS         : $LEGACY_DB_STATUS"

  if [ "$DJANGO_DESIRED" = "0" ] && \
     [ "$NGINX_DESIRED" = "0" ] && \
     [ "$EC2_STOPPING_OR_STOPPED" = "4" ] && \
     { [ "$DB_TIER_STATUS" = "stopping" ] || [ "$DB_TIER_STATUS" = "stopped" ]; } && \
     { [ "$LEGACY_DB_STATUS" = "stopping" ] || [ "$LEGACY_DB_STATUS" = "stopped" ]; }; then
    break
  fi

  sleep 5
done

echo "=== PharmaFlow 종료 요청 정상 반영 완료 ==="
echo "AWS가 백그라운드에서 최종 종료를 계속 진행합니다."

