#!/bin/bash
set -euo pipefail

export AWS_PAGER=""

echo "========================================"
echo " PharmaFlow 업무 종료"
echo "========================================"

# ---------------------------------------------------------
# 설정
# ---------------------------------------------------------

REGION="ap-northeast-2"

DJANGO_ASG="pharmaflow-django-asg"
NGINX_ASG="pharmaflow-nginx-asg"
DB_ID="pharmaflow-db-tier"

EKS_CLUSTER="pharmaflow-eks"
EKS_NODEGROUP="pharmaflow-eks-nodes"

CA_NAMESPACE="kube-system"
CA_DEPLOYMENT="cluster-autoscaler"

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
    --region "$REGION" \
    --filters \
      "Name=tag:Name,Values=$(IFS=,; echo "${FIXED_EC2_NAMES[*]}")" \
      "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text
}

get_asg_desired() {
  local ASG_NAME="$1"

  aws autoscaling describe-auto-scaling-groups \
    --region "$REGION" \
    --auto-scaling-group-names "$ASG_NAME" \
    --query 'AutoScalingGroups[0].DesiredCapacity' \
    --output text
}

get_asg_instance_count() {
  local ASG_NAME="$1"

  aws autoscaling describe-auto-scaling-groups \
    --region "$REGION" \
    --auto-scaling-group-names "$ASG_NAME" \
    --query 'length(AutoScalingGroups[0].Instances)' \
    --output text
}

get_eks_desired() {
  aws eks describe-nodegroup \
    --region "$REGION" \
    --cluster-name "$EKS_CLUSTER" \
    --nodegroup-name "$EKS_NODEGROUP" \
    --query 'nodegroup.scalingConfig.desiredSize' \
    --output text
}

get_eks_scaling() {
  aws eks describe-nodegroup \
    --region "$REGION" \
    --cluster-name "$EKS_CLUSTER" \
    --nodegroup-name "$EKS_NODEGROUP" \
    --query 'nodegroup.scalingConfig.[minSize,maxSize,desiredSize]' \
    --output text
}

get_eks_asg_name() {
  aws eks describe-nodegroup \
    --region "$REGION" \
    --cluster-name "$EKS_CLUSTER" \
    --nodegroup-name "$EKS_NODEGROUP" \
    --query 'nodegroup.resources.autoScalingGroups[0].name' \
    --output text
}

get_eks_asg_desired() {
  local ASG_NAME
  ASG_NAME=$(get_eks_asg_name)

  aws autoscaling describe-auto-scaling-groups \
    --region "$REGION" \
    --auto-scaling-group-names "$ASG_NAME" \
    --query 'AutoScalingGroups[0].DesiredCapacity' \
    --output text
}

# ---------------------------------------------------------
# 0. Cluster Autoscaler 중지
# ---------------------------------------------------------

echo
echo "[0/5] Cluster Autoscaler 중지"

CA_REPLICAS=$(kubectl get deployment "$CA_DEPLOYMENT" \
  -n "$CA_NAMESPACE" \
  -o jsonpath='{.spec.replicas}')

echo "현재 Cluster Autoscaler replicas: $CA_REPLICAS"

if [ "$CA_REPLICAS" != "0" ]; then
  kubectl scale deployment "$CA_DEPLOYMENT" \
    -n "$CA_NAMESPACE" \
    --replicas=0

  echo "Cluster Autoscaler replicas → 0 요청 완료"
else
  echo "Cluster Autoscaler는 이미 replicas=0"
fi

echo "Cluster Autoscaler Pod 종료 대기..."

for i in {1..30}; do
  CA_PODS=$(kubectl get pods \
    -n "$CA_NAMESPACE" \
    -l app=cluster-autoscaler \
    --no-headers 2>/dev/null | wc -l)

  echo "Cluster Autoscaler Pods: $CA_PODS"

  if [ "$CA_PODS" = "0" ]; then
    echo "Cluster Autoscaler 중지 완료"
    break
  fi

  if [ "$i" = "30" ]; then
    echo "ERROR: Cluster Autoscaler 종료 대기 시간 초과"
    exit 1
  fi

  sleep 2
done

# ---------------------------------------------------------
# 1. EKS / Legacy ASG 축소 요청
# ---------------------------------------------------------

echo
echo "[1/5] EKS / Legacy ASG 축소 요청"

EKS_SCALING=$(get_eks_scaling)

if [ "$EKS_SCALING" = $'0\t4\t0' ]; then
  echo "EKS Node Group은 이미 min=0 / desired=0 / max=4"
else
  echo "현재 EKS scaling: $EKS_SCALING"

  aws eks update-nodegroup-config \
    --region "$REGION" \
    --cluster-name "$EKS_CLUSTER" \
    --nodegroup-name "$EKS_NODEGROUP" \
    --scaling-config minSize=0,maxSize=4,desiredSize=0 \
    >/dev/null

  echo "EKS Node Group → min=0 / desired=0 / max=4 요청 완료"
fi

# ---------------------------------------------------------
# 1-1. EKS backing ASG 축소 확인
# ---------------------------------------------------------

echo
echo "EKS backing ASG Desired=0 대기..."

for i in {1..60}; do
  EKS_ASG_DESIRED=$(get_eks_asg_desired)

  echo "EKS backing ASG desired: $EKS_ASG_DESIRED / 0"

  if [ "$EKS_ASG_DESIRED" = "0" ]; then
    echo "EKS backing ASG 축소 요청 반영 완료"
    break
  fi

  if [ "$i" = "60" ]; then
    echo "ERROR: EKS backing ASG desired=0 대기 시간 초과"
    exit 1
  fi

  sleep 5
done

DJANGO_DESIRED=$(get_asg_desired "$DJANGO_ASG")

if [ "$DJANGO_DESIRED" != "0" ]; then
  aws autoscaling update-auto-scaling-group \
    --region "$REGION" \
    --auto-scaling-group-name "$DJANGO_ASG" \
    --min-size 0 \
    --desired-capacity 0

  echo "Django ASG → desired=0 요청 완료"
else
  echo "Django ASG는 이미 desired=0"
fi

NGINX_DESIRED=$(get_asg_desired "$NGINX_ASG")

if [ "$NGINX_DESIRED" != "0" ]; then
  aws autoscaling update-auto-scaling-group \
    --region "$REGION" \
    --auto-scaling-group-name "$NGINX_ASG" \
    --min-size 0 \
    --desired-capacity 0

  echo "Nginx ASG → desired=0 요청 완료"
else
  echo "Nginx ASG는 이미 desired=0"
fi

# ---------------------------------------------------------
# 2. EKS / Legacy ASG 축소 진행 확인
# ---------------------------------------------------------

echo
echo "[2/5] EKS / Legacy ASG 축소 진행 확인"
echo "최대 2분 동안 AWS 축소 상태를 확인합니다."
echo "※ Kubernetes Node 수는 참고값이며 완료 판정에는 사용하지 않습니다."

for i in {1..12}; do
  EKS_DESIRED=$(get_eks_desired)

  DJANGO_DESIRED=$(get_asg_desired "$DJANGO_ASG")
  NGINX_DESIRED=$(get_asg_desired "$NGINX_ASG")

  DJANGO_COUNT=$(get_asg_instance_count "$DJANGO_ASG")
  NGINX_COUNT=$(get_asg_instance_count "$NGINX_ASG")

  NODE_COUNT=$(kubectl get nodes \
    --no-headers 2>/dev/null \
    | wc -l || true)

  echo "----------------------------------------"
  echo "EKS desired          : $EKS_DESIRED"
  echo "Kubernetes nodes     : $NODE_COUNT (참고)"
  echo "Django ASG desired   : $DJANGO_DESIRED"
  echo "Django ASG instances : $DJANGO_COUNT"
  echo "Nginx ASG desired    : $NGINX_DESIRED"
  echo "Nginx ASG instances  : $NGINX_COUNT"

  if [ "$EKS_DESIRED" = "0" ] && \
     [ "$DJANGO_DESIRED" = "0" ] && \
     [ "$NGINX_DESIRED" = "0" ] && \
     [ "$DJANGO_COUNT" = "0" ] && \
     [ "$NGINX_COUNT" = "0" ]; then

    echo "EKS / Legacy ASG 축소 요청 정상 반영"
    break
  fi

  if [ "$i" = "12" ]; then
    echo "INFO: 일부 인스턴스가 아직 종료 중일 수 있습니다."
    echo "INFO: desired=0 요청은 유지되며 나머지 종료 절차를 계속 진행합니다."
    break
  fi

  sleep 10
done

# ---------------------------------------------------------
# 3. 고정 EC2 / RDS 중지 요청
# ---------------------------------------------------------

echo
echo "[3/5] 고정 EC2 / RDS 중지 요청"

EC2_IDS=$(get_fixed_ec2_ids)
RUNNING_EC2_IDS=""

if [ -n "$EC2_IDS" ]; then
  RUNNING_EC2_IDS=$(aws ec2 describe-instances \
    --region "$REGION" \
    --instance-ids $EC2_IDS \
    --query 'Reservations[].Instances[?State.Name==`running`].InstanceId' \
    --output text)
fi

if [ -n "$RUNNING_EC2_IDS" ]; then
  echo "중지 대상 EC2: $RUNNING_EC2_IDS"

  aws ec2 stop-instances \
    --region "$REGION" \
    --instance-ids $RUNNING_EC2_IDS \
    >/dev/null

  echo "고정 EC2 중지 요청 완료"
else
  echo "실행 중인 고정 EC2 없음"
fi

DB_STATUS=$(aws rds describe-db-instances \
  --region "$REGION" \
  --db-instance-identifier "$DB_ID" \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text)

if [ "$DB_STATUS" = "available" ]; then
  echo "RDS 중지 요청: $DB_ID"

  aws rds stop-db-instance \
    --region "$REGION" \
    --db-instance-identifier "$DB_ID" \
    >/dev/null

  echo "RDS 중지 요청 완료"
else
  echo "RDS 현재 상태: $DB_STATUS"
fi

# ---------------------------------------------------------
# 4. 최종 종료 상태 확인
# ---------------------------------------------------------

echo
echo "[4/5] 최종 종료 상태 확인"
echo "최대 5분 동안 종료 상태를 확인합니다."

EC2_IDS=$(get_fixed_ec2_ids)
EC2_TOTAL=0

if [ -n "$EC2_IDS" ]; then
  EC2_TOTAL=$(wc -w <<< "$EC2_IDS")
fi

FINAL_OK=false

for i in {1..30}; do
  EKS_DESIRED=$(get_eks_desired)

  DJANGO_DESIRED=$(get_asg_desired "$DJANGO_ASG")
  NGINX_DESIRED=$(get_asg_desired "$NGINX_ASG")

  DJANGO_COUNT=$(get_asg_instance_count "$DJANGO_ASG")
  NGINX_COUNT=$(get_asg_instance_count "$NGINX_ASG")

  EC2_STOPPED=0

  if [ "$EC2_TOTAL" -gt 0 ]; then
    EC2_STOPPED=$(aws ec2 describe-instances \
      --region "$REGION" \
      --instance-ids $EC2_IDS \
      --query 'length(Reservations[].Instances[] | [?State.Name==`stopping` || State.Name==`stopped`])' \
      --output text)
  fi

  DB_STATUS=$(aws rds describe-db-instances \
    --region "$REGION" \
    --db-instance-identifier "$DB_ID" \
    --query 'DBInstances[0].DBInstanceStatus' \
    --output text)

  echo "----------------------------------------"
  echo "EKS Node Group desired : $EKS_DESIRED"
  echo "Django ASG desired     : $DJANGO_DESIRED"
  echo "Django ASG instances   : $DJANGO_COUNT"
  echo "Nginx ASG desired      : $NGINX_DESIRED"
  echo "Nginx ASG instances    : $NGINX_COUNT"
  echo "EC2 stopping/stopped   : $EC2_STOPPED / $EC2_TOTAL"
  echo "RDS                    : $DB_STATUS"

  if [ "$EKS_DESIRED" = "0" ] && \
     [ "$DJANGO_DESIRED" = "0" ] && \
     [ "$NGINX_DESIRED" = "0" ] && \
     [ "$DJANGO_COUNT" = "0" ] && \
     [ "$NGINX_COUNT" = "0" ] && \
     [ "$EC2_STOPPED" = "$EC2_TOTAL" ] && \
     { [ "$DB_STATUS" = "stopping" ] || \
       [ "$DB_STATUS" = "stopped" ]; }; then

    FINAL_OK=true
    break
  fi

  if [ "$i" = "30" ]; then
    echo "WARNING: 일부 AWS 리소스가 아직 종료 중입니다."
    break
  fi

  sleep 10
done

# ---------------------------------------------------------
# 5. 결과 출력
# ---------------------------------------------------------

echo
echo "[5/5] 종료 결과"

echo
echo "========================================"

if [ "$FINAL_OK" = true ]; then
  echo " PharmaFlow 종료 요청 정상 반영 완료"
else
  echo " PharmaFlow 종료 요청 완료 / 일부 리소스 정리 중"
fi

echo "========================================"
echo "EKS Nodes  : Desired 0"
echo "Legacy ASG : Desired 0"
echo "EC2        : stopping / stopped"
echo "RDS        : stopping / stopped"
echo
echo "※ Kubernetes Node 객체는 EC2 종료 후 잠시 남아 있을 수 있습니다."
echo "※ EKS Control Plane, ALB, EFS, Route 53, WAF,"
echo "   ACM, ECR 등은 Stop 대상이 아닙니다."
