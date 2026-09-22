#!/bin/bash
set -euo pipefail

export AWS_PAGER=""

echo "========================================"
echo " PharmaFlow 업무 시작"
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
EKS_NAMESPACE="pharmaflow-dev"

CA_NAMESPACE="kube-system"
CA_DEPLOYMENT="cluster-autoscaler"

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
    --region "$REGION" \
    --filters \
      "Name=tag:Name,Values=$(IFS=,; echo "${FIXED_EC2_NAMES[*]}")" \
      "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text
}

get_inservice_count() {
  local ASG_NAME="$1"

  aws autoscaling describe-auto-scaling-groups \
    --region "$REGION" \
    --auto-scaling-group-names "$ASG_NAME" \
    --query 'length(AutoScalingGroups[0].Instances[?LifecycleState==`InService` && HealthStatus==`Healthy`])' \
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
# 1. 고정 EC2 시작
# ---------------------------------------------------------

echo
echo "[1/8] 고정 EC2 시작"

EC2_IDS=$(get_fixed_ec2_ids)
STOPPED_EC2_IDS=""

if [ -n "$EC2_IDS" ]; then
  STOPPED_EC2_IDS=$(aws ec2 describe-instances \
    --region "$REGION" \
    --instance-ids $EC2_IDS \
    --query 'Reservations[].Instances[?State.Name==`stopped`].InstanceId' \
    --output text)
fi

if [ -n "$STOPPED_EC2_IDS" ]; then
  echo "시작 대상 EC2: $STOPPED_EC2_IDS"

  aws ec2 start-instances \
    --region "$REGION" \
    --instance-ids $STOPPED_EC2_IDS \
    >/dev/null

  echo "고정 EC2 시작 요청 완료"
else
  echo "시작할 stopped EC2 없음"
fi

EC2_IDS=$(get_fixed_ec2_ids)

if [ -n "$EC2_IDS" ]; then
  echo "고정 EC2 Running 대기..."

  aws ec2 wait instance-running \
    --region "$REGION" \
    --instance-ids $EC2_IDS

  echo "고정 EC2 Running 완료"
fi

# ---------------------------------------------------------
# 2. RDS 시작 및 Available 대기
# ---------------------------------------------------------

echo
echo "[2/8] RDS 시작"

DB_STATUS=$(aws rds describe-db-instances \
  --region "$REGION" \
  --db-instance-identifier "$DB_ID" \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text)

echo "RDS 현재 상태: $DB_STATUS"

# Stop 직후 Start를 실행한 경우 stopping 완료 후 다시 시작한다.
if [ "$DB_STATUS" = "stopping" ]; then
  echo "RDS가 종료 중입니다."
  echo "stopped 상태까지 기다린 후 다시 시작합니다."

  aws rds wait db-instance-stopped \
    --region "$REGION" \
    --db-instance-identifier "$DB_ID"

  DB_STATUS="stopped"

  echo "RDS stopped 확인 완료"
fi

if [ "$DB_STATUS" = "stopped" ]; then
  aws rds start-db-instance \
    --region "$REGION" \
    --db-instance-identifier "$DB_ID" \
    >/dev/null

  echo "RDS 시작 요청 완료"

elif [ "$DB_STATUS" = "available" ]; then
  echo "RDS는 이미 available 상태입니다."

else
  echo "RDS 상태가 전환 중입니다: $DB_STATUS"
fi

echo "RDS available 대기..."

aws rds wait db-instance-available \
  --region "$REGION" \
  --db-instance-identifier "$DB_ID"

echo "RDS available 완료"

# ---------------------------------------------------------
# 3. Legacy Django / Nginx ASG 시작
# ---------------------------------------------------------

echo
echo "[3/8] Legacy Django / Nginx ASG 시작"

aws autoscaling update-auto-scaling-group \
  --region "$REGION" \
  --auto-scaling-group-name "$DJANGO_ASG" \
  --min-size 0 \
  --desired-capacity 2

aws autoscaling update-auto-scaling-group \
  --region "$REGION" \
  --auto-scaling-group-name "$NGINX_ASG" \
  --min-size 0 \
  --desired-capacity 2

echo "Legacy ASG Desired Capacity → 2 요청 완료"

# ---------------------------------------------------------
# 4. Legacy ASG 정상화 대기
# ---------------------------------------------------------

echo
echo "[4/8] Legacy ASG 정상화 대기"

for i in {1..60}; do
  DJANGO_INSERVICE=$(get_inservice_count "$DJANGO_ASG")
  NGINX_INSERVICE=$(get_inservice_count "$NGINX_ASG")

  echo "Django Healthy InService : $DJANGO_INSERVICE / 2"
  echo "Nginx Healthy InService  : $NGINX_INSERVICE / 2"

  if [ "$DJANGO_INSERVICE" = "2" ] && \
     [ "$NGINX_INSERVICE" = "2" ]; then

    echo "Legacy ASG 인스턴스 정상화 완료"
    break
  fi

  if [ "$i" = "60" ]; then
    echo "ERROR: Legacy ASG 정상화 대기 시간 초과"
    exit 1
  fi

  sleep 10
done

# ---------------------------------------------------------
# 5. EKS Managed Node Group 시작
# ---------------------------------------------------------

echo
echo "[5/8] EKS Managed Node Group 시작"

NODEGROUP_STATUS=$(aws eks describe-nodegroup \
  --region "$REGION" \
  --cluster-name "$EKS_CLUSTER" \
  --nodegroup-name "$EKS_NODEGROUP" \
  --query 'nodegroup.status' \
  --output text)

echo "EKS Node Group 상태: $NODEGROUP_STATUS"

EKS_SCALING=$(get_eks_scaling)

echo "현재 EKS scaling: $EKS_SCALING"

if [ "$EKS_SCALING" = $'3\t4\t3' ]; then
  echo "EKS Node Group은 이미 min=3 / desired=3 / max=4"
else
  aws eks update-nodegroup-config \
    --region "$REGION" \
    --cluster-name "$EKS_CLUSTER" \
    --nodegroup-name "$EKS_NODEGROUP" \
    --scaling-config minSize=3,maxSize=4,desiredSize=3 \
    >/dev/null

  echo "EKS Node Group → min=3 / desired=3 / max=4 요청 완료"

  echo "Node Group ACTIVE 대기..."

  aws eks wait nodegroup-active \
    --region "$REGION" \
    --cluster-name "$EKS_CLUSTER" \
    --nodegroup-name "$EKS_NODEGROUP"

  echo "EKS Node Group ACTIVE"
fi

# ---------------------------------------------------------
# 5-1. EKS backing ASG 정상화 확인
# ---------------------------------------------------------

echo
echo "EKS backing ASG Desired=3 대기..."

for i in {1..60}; do
  EKS_ASG_DESIRED=$(get_eks_asg_desired)

  echo "EKS backing ASG desired: $EKS_ASG_DESIRED / 3"

  if [ "$EKS_ASG_DESIRED" = "3" ]; then
    echo "EKS backing ASG 정상화 완료"
    break
  fi

  if [ "$i" = "60" ]; then
    echo "ERROR: EKS backing ASG desired=2 대기 시간 초과"
    exit 1
  fi

  sleep 5
done

# ---------------------------------------------------------
# 6. Kubernetes Node / Metrics 정상화
# ---------------------------------------------------------

echo
echo "[6/8] EKS Node / System 정상화 대기"

for i in {1..60}; do
  READY_NODES=$(kubectl get nodes \
    --no-headers 2>/dev/null \
    | awk '$2=="Ready"{c++} END{print c+0}')

  echo "EKS Ready Nodes: $READY_NODES / 3"

  if [ "$READY_NODES" -ge 3 ]; then
    echo "EKS Node 정상화 완료"
    break
  fi

  if [ "$i" = "60" ]; then
    echo "ERROR: EKS Node Ready 대기 시간 초과"
    exit 1
  fi

  sleep 10
done

echo
echo "Metrics API 확인..."

METRICS_OK=false

for i in {1..30}; do
  METRICS_AVAILABLE=$(kubectl get apiservice \
    v1beta1.metrics.k8s.io \
    -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' \
    2>/dev/null || true)

  if [ "$METRICS_AVAILABLE" = "True" ]; then
    echo "Metrics API Available=True"
    METRICS_OK=true
    break
  fi

  if [ "$i" = "30" ]; then
    echo "WARNING: Metrics API가 아직 Available 상태가 아닙니다."
    break
  fi

  sleep 5
done

# ---------------------------------------------------------
# 6-1. Cluster Autoscaler 정상화
# ---------------------------------------------------------

echo
echo "Cluster Autoscaler 정상화"

CA_REPLICAS=$(kubectl get deployment "$CA_DEPLOYMENT" \
  -n "$CA_NAMESPACE" \
  -o jsonpath='{.spec.replicas}')

echo "현재 Cluster Autoscaler replicas: $CA_REPLICAS"

if [ "$CA_REPLICAS" != "1" ]; then
  kubectl scale deployment "$CA_DEPLOYMENT" \
    -n "$CA_NAMESPACE" \
    --replicas=1

  echo "Cluster Autoscaler replicas → 1 요청 완료"
else
  echo "Cluster Autoscaler는 이미 replicas=1"
fi

kubectl rollout status deployment/"$CA_DEPLOYMENT" \
  -n "$CA_NAMESPACE" \
  --timeout=180s

echo "Cluster Autoscaler 정상화 완료"

# ---------------------------------------------------------
# 7. PharmaFlow EKS Workload 정상화
# ---------------------------------------------------------

echo
echo "[7/8] PharmaFlow EKS Workload 정상화"

kubectl rollout status \
  deployment/django \
  -n "$EKS_NAMESPACE" \
  --timeout=300s

kubectl rollout status \
  deployment/pharmaflow-nginx \
  -n "$EKS_NAMESPACE" \
  --timeout=300s

echo
echo "EKS Workloads:"

kubectl get deployment \
  django pharmaflow-nginx \
  -n "$EKS_NAMESPACE"

echo
echo "HPA:"

kubectl get hpa \
  django \
  -n "$EKS_NAMESPACE" \
  || echo "WARNING: Django HPA 확인 실패"

echo
echo "Metrics:"

kubectl top pods \
  -n "$EKS_NAMESPACE" \
  2>/dev/null \
  || echo "INFO: Pod metrics가 아직 준비되지 않았습니다."

# ---------------------------------------------------------
# 8. 외부 서비스 정상화 대기 및 최종 확인
# ---------------------------------------------------------

echo
echo "[8/8] PharmaFlow 외부 서비스 정상화 대기"
echo "최대 3분 동안 Site / Live / Ready 상태를 확인합니다."

SITE_CODE="000"
LIVE_CODE="000"
READY_CODE="000"
SERVICE_OK=false

for i in {1..36}; do
  SITE_CODE=$(curl -sS -o /dev/null \
    -w '%{http_code}' \
    --connect-timeout 5 \
    --max-time 10 \
    https://pharmaflow.homes/ \
    2>/dev/null || true)

  LIVE_CODE=$(curl -sS -o /dev/null \
    -w '%{http_code}' \
    --connect-timeout 5 \
    --max-time 10 \
    https://pharmaflow.homes/health/live/ \
    2>/dev/null || true)

  READY_CODE=$(curl -sS -o /dev/null \
    -w '%{http_code}' \
    --connect-timeout 5 \
    --max-time 10 \
    https://pharmaflow.homes/health/ready/ \
    2>/dev/null || true)

  echo "Site=$SITE_CODE Live=$LIVE_CODE Ready=$READY_CODE"

  if [ "$SITE_CODE" = "200" ] && \
     [ "$LIVE_CODE" = "200" ] && \
     [ "$READY_CODE" = "200" ]; then

    SERVICE_OK=true
    echo "외부 서비스 정상화 완료"
    break
  fi

  if [ "$i" = "36" ]; then
    echo "WARNING: 외부 서비스 정상화 대기 시간 초과"
    break
  fi

  sleep 5
done

# ---------------------------------------------------------
# 최종 상태 출력
# ---------------------------------------------------------

echo
echo "===== EKS NODES ====="

kubectl get nodes \
  -L topology.kubernetes.io/zone

echo
echo "===== EKS APPLICATION PODS ====="

kubectl get pods \
  -n "$EKS_NAMESPACE" \
  -l 'app in (django,pharmaflow-nginx)' \
  -o wide

echo
echo "===== HPA FINAL ====="

kubectl get hpa \
  django \
  -n "$EKS_NAMESPACE" \
  || true

echo
echo "===== SERVICE FINAL ====="
echo "Site  : HTTP $SITE_CODE"
echo "Live  : HTTP $LIVE_CODE"
echo "Ready : HTTP $READY_CODE"

echo
echo "========================================"

if [ "$SERVICE_OK" = true ]; then
  echo " PharmaFlow 정상 기동 완료"
else
  echo " WARNING: PharmaFlow 일부 서비스 확인 필요"
fi

echo "========================================"
echo "Legacy ASG : Desired 2"
echo "EKS Nodes  : Desired 3"
echo "RDS        : available"

if [ "$METRICS_OK" = true ]; then
  echo "Metrics    : API Available"
else
  echo "Metrics    : 확인 필요"
fi

echo "Service    : Site=$SITE_CODE / Live=$LIVE_CODE / Ready=$READY_CODE"

if [ "$SERVICE_OK" != true ]; then
  echo
  echo "확인 명령:"
  echo "kubectl get pods -n $EKS_NAMESPACE -o wide"
  echo "kubectl get events -n $EKS_NAMESPACE --sort-by=.lastTimestamp"
  echo "kubectl get hpa -n $EKS_NAMESPACE"
  echo "kubectl top pods -n $EKS_NAMESPACE"
fi
