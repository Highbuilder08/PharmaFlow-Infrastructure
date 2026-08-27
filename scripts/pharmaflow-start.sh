#!/bin/bash
set -euo pipefail

export AWS_PAGER=""

echo "========================================"
echo " PharmaFlow 업무 시작"
echo "========================================"

# ---------------------------------------------------------
# 설정
# ---------------------------------------------------------

DJANGO_ASG="pharmaflow-django-asg"
NGINX_ASG="pharmaflow-nginx-asg"
DB_ID="pharmaflow-db-tier"

FIXED_EC2_NAMES=(
  "pharmaflow-nat"
  "pharmaflow-wireguard"
  "pharmaflow-bastion"
  "pharmaflow-django-base"
  "pharmaflow-nginx"
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

get_inservice_count() {
  local ASG_NAME="$1"

  aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --query 'length(AutoScalingGroups[0].Instances[?LifecycleState==`InService` && HealthStatus==`Healthy`])' \
    --output text
}

# ---------------------------------------------------------
# 1. 고정 EC2 시작
# ---------------------------------------------------------

echo
echo "[1/5] 고정 EC2 시작"

EC2_IDS=$(get_fixed_ec2_ids)

STOPPED_EC2_IDS=""

if [ -n "$EC2_IDS" ]; then
  STOPPED_EC2_IDS=$(aws ec2 describe-instances \
    --instance-ids $EC2_IDS \
    --query 'Reservations[].Instances[?State.Name==`stopped`].InstanceId' \
    --output text)
fi

if [ -n "$STOPPED_EC2_IDS" ]; then
  echo "시작 대상 EC2: $STOPPED_EC2_IDS"

  aws ec2 start-instances \
    --instance-ids $STOPPED_EC2_IDS \
    >/dev/null
else
  echo "시작할 stopped EC2 없음"
fi

# 고정 EC2 전체가 running이 될 때까지 기다림
EC2_IDS=$(get_fixed_ec2_ids)

if [ -n "$EC2_IDS" ]; then
  echo "고정 EC2 Running 대기..."
  aws ec2 wait instance-running \
    --instance-ids $EC2_IDS

  echo "고정 EC2 Running 완료"
fi

# ---------------------------------------------------------
# 2. RDS 시작 및 Available 대기
# ---------------------------------------------------------

echo
echo "[2/5] RDS 시작"

DB_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier "$DB_ID" \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text)

if [ "$DB_STATUS" = "stopped" ]; then
  aws rds start-db-instance \
    --db-instance-identifier "$DB_ID" \
    >/dev/null

  echo "RDS 시작 요청 완료"
else
  echo "RDS 현재 상태: $DB_STATUS"
fi

echo "RDS available 대기..."

aws rds wait db-instance-available \
  --db-instance-identifier "$DB_ID"

echo "RDS available 완료"

# ---------------------------------------------------------
# 3. Django / Nginx ASG 시작
# ---------------------------------------------------------

echo
echo "[3/5] Django / Nginx ASG Desired Capacity 2"

aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name "$DJANGO_ASG" \
  --min-size 0 \
  --desired-capacity 2

aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name "$NGINX_ASG" \
  --min-size 0 \
  --desired-capacity 2

echo "ASG Desired Capacity → 2 요청 완료"

# ---------------------------------------------------------
# 4. ASG Healthy / InService 2대 대기
# ---------------------------------------------------------

echo
echo "[4/5] ASG 정상화 대기"

for i in {1..90}; do
  DJANGO_INSERVICE=$(get_inservice_count "$DJANGO_ASG")
  NGINX_INSERVICE=$(get_inservice_count "$NGINX_ASG")

  echo "Django Healthy InService : $DJANGO_INSERVICE / 2"
  echo "Nginx Healthy InService  : $NGINX_INSERVICE / 2"

  if [ "$DJANGO_INSERVICE" = "2" ] && \
     [ "$NGINX_INSERVICE" = "2" ]; then
    echo "ASG 인스턴스 정상화 완료"
    break
  fi

  if [ "$i" = "90" ]; then
    echo "ERROR: ASG 정상화 대기 시간 초과"
    exit 1
  fi

  sleep 10
done

# ---------------------------------------------------------
# 5. 서비스 최종 확인
# ---------------------------------------------------------

echo
echo "[5/5] PharmaFlow 서비스 확인"

SITE_CODE=$(curl -sS -o /dev/null \
  -w '%{http_code}' \
  --connect-timeout 10 \
  https://pharmaflow.homes/ || true)

LIVE_CODE=$(curl -sS -o /dev/null \
  -w '%{http_code}' \
  --connect-timeout 10 \
  https://pharmaflow.homes/health/live/ || true)

READY_CODE=$(curl -sS -o /dev/null \
  -w '%{http_code}' \
  --connect-timeout 10 \
  https://pharmaflow.homes/health/ready/ || true)

echo "Site  : HTTP $SITE_CODE"
echo "Live  : HTTP $LIVE_CODE"
echo "Ready : HTTP $READY_CODE"

if [ "$SITE_CODE" = "200" ] && \
   [ "$LIVE_CODE" = "200" ] && \
   [ "$READY_CODE" = "200" ]; then

  echo
  echo "========================================"
  echo " PharmaFlow 정상 기동 완료"
  echo "========================================"

else
  echo
  echo "WARNING: AWS 인프라는 시작됐지만 서비스가 아직 준비 중일 수 있습니다."
  echo "잠시 후 health check를 다시 확인하세요."
fi

