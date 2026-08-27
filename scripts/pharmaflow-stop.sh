#!/bin/bash
set -euo pipefail

export AWS_PAGER=""

echo "========================================"
echo " PharmaFlow 업무 종료"
echo "========================================"

# ---------------------------------------------------------
# 설정
# ---------------------------------------------------------

DJANGO_ASG="pharmaflow-django-asg"
NGINX_ASG="pharmaflow-nginx-asg"
DB_ID="pharmaflow-db-tier"

FIXED_EC2_NAMES=(
  "pharmaflow-django-base"
  "pharmaflow-nginx"
  "pharmaflow-bastion"
  "pharmaflow-wireguard"
  "pharmaflow-nat"
)

# ---------------------------------------------------------
# 함수
# ---------------------------------------------------------

get_fixed_ec2_ids() {
  aws ec2 describe-instances \
    --filters \
      "Name=tag:Name,Values=$(IFS=,; echo "${FIXED_EC2_NAMES[*]}")" \
      "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text
}

# ---------------------------------------------------------
# 1. ASG 축소
# ---------------------------------------------------------

echo
echo "[1/4] Django / Nginx ASG 축소"

aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name "$DJANGO_ASG" \
  --min-size 0 \
  --desired-capacity 0

aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name "$NGINX_ASG" \
  --min-size 0 \
  --desired-capacity 0

echo "ASG Desired Capacity → 0 요청 완료"

# ---------------------------------------------------------
# 2. ASG 인스턴스 종료 대기
# ---------------------------------------------------------

echo
echo "[2/4] ASG 인스턴스 종료 확인"

for i in {1..60}; do
  DJANGO_COUNT=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$DJANGO_ASG" \
    --query 'length(AutoScalingGroups[0].Instances)' \
    --output text)

  NGINX_COUNT=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$NGINX_ASG" \
    --query 'length(AutoScalingGroups[0].Instances)' \
    --output text)

  echo "Django ASG instances : $DJANGO_COUNT"
  echo "Nginx ASG instances  : $NGINX_COUNT"

  if [ "$DJANGO_COUNT" = "0" ] && [ "$NGINX_COUNT" = "0" ]; then
    echo "ASG 인스턴스 종료 완료"
    break
  fi

  if [ "$i" = "60" ]; then
    echo "ERROR: ASG 인스턴스 종료 대기 시간 초과"
    exit 1
  fi

  sleep 10
done

# ---------------------------------------------------------
# 3. 고정 EC2 / RDS 중지
# ---------------------------------------------------------

echo
echo "[3/4] 고정 EC2 / RDS 중지"

EC2_IDS=$(get_fixed_ec2_ids)

RUNNING_EC2_IDS=""

if [ -n "$EC2_IDS" ]; then
  RUNNING_EC2_IDS=$(aws ec2 describe-instances \
    --instance-ids $EC2_IDS \
    --query 'Reservations[].Instances[?State.Name==`running`].InstanceId' \
    --output text)
fi

if [ -n "$RUNNING_EC2_IDS" ]; then
  echo "중지 대상 EC2: $RUNNING_EC2_IDS"

  aws ec2 stop-instances \
    --instance-ids $RUNNING_EC2_IDS \
    >/dev/null
else
  echo "실행 중인 고정 EC2 없음"
fi

DB_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier "$DB_ID" \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text)

if [ "$DB_STATUS" = "available" ]; then
  echo "RDS 중지 요청: $DB_ID"

  aws rds stop-db-instance \
    --db-instance-identifier "$DB_ID" \
    >/dev/null
else
  echo "RDS 현재 상태: $DB_STATUS"
fi

# ---------------------------------------------------------
# 4. 종료 요청 상태 확인
# ---------------------------------------------------------

echo
echo "[4/4] 종료 상태 확인"

EC2_IDS=$(get_fixed_ec2_ids)
EC2_TOTAL=0

if [ -n "$EC2_IDS" ]; then
  EC2_TOTAL=$(wc -w <<< "$EC2_IDS")
fi

for i in {1..60}; do
  DJANGO_DESIRED=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$DJANGO_ASG" \
    --query 'AutoScalingGroups[0].DesiredCapacity' \
    --output text)

  NGINX_DESIRED=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$NGINX_ASG" \
    --query 'AutoScalingGroups[0].DesiredCapacity' \
    --output text)

  EC2_STOPPED=0

  if [ "$EC2_TOTAL" -gt 0 ]; then
    EC2_STOPPED=$(aws ec2 describe-instances \
      --instance-ids $EC2_IDS \
      --query 'length(Reservations[].Instances[] | [?State.Name==`stopping` || State.Name==`stopped`])' \
      --output text)
  fi

  DB_STATUS=$(aws rds describe-db-instances \
    --db-instance-identifier "$DB_ID" \
    --query 'DBInstances[0].DBInstanceStatus' \
    --output text)

  echo "----------------------------------------"
  echo "Django ASG desired : $DJANGO_DESIRED"
  echo "Nginx ASG desired  : $NGINX_DESIRED"
  echo "EC2 stopping/stopped: $EC2_STOPPED / $EC2_TOTAL"
  echo "RDS                : $DB_STATUS"

  if [ "$DJANGO_DESIRED" = "0" ] && \
     [ "$NGINX_DESIRED" = "0" ] && \
     [ "$EC2_STOPPED" = "$EC2_TOTAL" ] && \
     { [ "$DB_STATUS" = "stopping" ] || [ "$DB_STATUS" = "stopped" ]; }; then
    break
  fi

  if [ "$i" = "60" ]; then
    echo "WARNING: 일부 리소스가 아직 종료 중입니다."
    break
  fi

  sleep 10
done

echo
echo "========================================"
echo " PharmaFlow 종료 요청 정상 반영 완료"
echo "========================================"
echo "ASG : Desired 0"
echo "EC2 : stopping / stopped"
echo "RDS : stopping / stopped"
echo
echo "※ ALB, EFS, Route 53, WAF 등은 Stop 대상이 아닙니다."

