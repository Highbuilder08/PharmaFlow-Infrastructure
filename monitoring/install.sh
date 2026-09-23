#!/usr/bin/env bash
set -euo pipefail

RELEASE="pharmaflow-monitoring"
NAMESPACE="monitoring"
CHART="prometheus-community/kube-prometheus-stack"
CHART_VERSION="91.5.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES_FILE="${SCRIPT_DIR}/values-pharmaflow.yaml"
DASHBOARD_FILE="${SCRIPT_DIR}/dashboards/pharmaflow-dashboard-configmap.yaml"

echo "========================================"
echo " PharmaFlow Monitoring Installation"
echo "========================================"

echo
echo "===== PRECHECK ====="

command -v helm >/dev/null
command -v kubectl >/dev/null

test -f "${VALUES_FILE}"
test -f "${DASHBOARD_FILE}"

kubectl cluster-info >/dev/null

echo "PRECHECK=PASS"

echo
echo "===== HELM REPOSITORY ====="

if ! helm repo list 2>/dev/null \
  | awk '{print $1}' \
  | grep -qx 'prometheus-community'
then
  helm repo add prometheus-community \
    https://prometheus-community.github.io/helm-charts
fi

helm repo update

echo
echo "===== MONITORING STACK ====="

helm upgrade --install "${RELEASE}" "${CHART}" \
  --version "${CHART_VERSION}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  -f "${VALUES_FILE}" \
  --wait \
  --timeout 10m

echo
echo "===== GRAFANA DASHBOARD ====="

kubectl apply \
  -f "${DASHBOARD_FILE}"

echo
echo "===== RESULT ====="

helm status "${RELEASE}" \
  -n "${NAMESPACE}" \
  | grep -E 'NAME:|STATUS:|REVISION:'

kubectl get configmap pharmaflow-grafana-dashboard \
  -n "${NAMESPACE}" \
  -o custom-columns='NAME:.metadata.name,LABEL:.metadata.labels.grafana_dashboard'

echo
echo "MONITORING_INSTALL=PASS"
