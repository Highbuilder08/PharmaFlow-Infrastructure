#!/bin/bash
set -e

export AWS_PAGER=""

echo "=== PharmaFlow 업무 시작 ==="

# ---------------------------------------------------------
# 리소스 ID 조회
# ---------------------------------------------------------

NAT_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=pharmaflow-nat" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

BASTION_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=pharmaflow-bastion" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

DJANGO_BASE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=pharmaflow-django-base" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

NGINX_BASE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=pharmaflow-nginx" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

EC2_IDS=""

for INSTANCE_ID in \
  "$NAT_ID" \
  "$BASTION_ID" \
  "$DJANGO_BASE_ID" \
  "$NGINX_BASE_ID"
do
  if [ "$INSTANCE_ID" != "None" ] && [ -n "$INSTANCE_ID" ]; then
    EC2_IDS="$EC2_IDS $INSTANCE_ID"
  fi
done

# ---------------------------------------------------------
# 1. 고정 EC2 / DB Tier RDS 시작 요청
# ---------------------------------------------------------

echo "[1/3] 고정 EC2 / DB Tier RDS 시작 요청"

if [ -n "$EC2_IDS" ]; then
  aws ec2 start-instances \
    --instance-ids $EC2_IDS \
    >/dev/null
fi

DB_TIER_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier pharmaflow-db-tier \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text)

if [ "$DB_TIER_STATUS" = "stopped" ]; then
  aws rds start-db-instance \
    --db-instance-identifier pharmaflow-db-tier \
    >/dev/null
fi

echo "고정 EC2 / DB Tier RDS 시작 요청 완료"

# ---------------------------------------------------------
# 2. ASG desired capacity 2 적용
# ---------------------------------------------------------

echo "[2/3] Django / Nginx ASG desired capacity 2 적용"

aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name pharmaflow-django-asg \
  --min-size 0 \
  --desired-capacity 2

aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name pharmaflow-nginx-asg \
  --min-size 0 \
  --desired-capacity 2

echo "ASG desired capacity 2 적용 요청 완료"

# ---------------------------------------------------------
# 3. 시작 요청 반영 확인
# ---------------------------------------------------------

echo "[3/3] 시작 요청 반영 확인"

while true; do
  EC2_STARTING_OR_RUNNING=0

  if [ -n "$EC2_IDS" ]; then
    EC2_STARTING_OR_RUNNING=$(aws ec2 describe-instances \
      --instance-ids $EC2_IDS \
      --query 'length(Reservations[].Instances[] | [?State.Name==`pending` || State.Name==`running`])' \
      --output text)
  fi

  DB_TIER_STATUS=$(aws rds describe-db-instances \
    --db-instance-identifier pharmaflow-db-tier \
    --query 'DBInstances[0].DBInstanceStatus' \
    --output text)

  DJANGO_DESIRED=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names pharmaflow-django-asg \
    --query 'AutoScalingGroups[0].DesiredCapacity' \
    --output text)

  NGINX_DESIRED=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names pharmaflow-nginx-asg \
    --query 'AutoScalingGroups[0].DesiredCapacity' \
    --output text)

  echo "EC2 시작 진행 수    : $EC2_STARTING_OR_RUNNING / 4"
  echo "DB Tier RDS 상태    : $DB_TIER_STATUS"
  echo "Django ASG desired  : $DJANGO_DESIRED"
  echo "Nginx ASG desired   : $NGINX_DESIRED"

  if [ "$EC2_STARTING_OR_RUNNING" = "4" ] && \
     { [ "$DB_TIER_STATUS" = "starting" ] || [ "$DB_TIER_STATUS" = "available" ]; } && \
     [ "$DJANGO_DESIRED" = "2" ] && \
     [ "$NGINX_DESIRED" = "2" ]; then
    break
  fi

  sleep 5
done

echo "=== PharmaFlow 시작 요청 정상 반영 완료 ==="
echo "AWS가 백그라운드에서 최종 기동을 계속 진행합니다."

