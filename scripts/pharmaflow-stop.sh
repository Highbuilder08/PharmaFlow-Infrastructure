#!/bin/bash
set -e

echo "=== PharmaFlow 업무 종료 ==="

echo "[1/1] Django ASG 축소: 2 -> 0"

aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name pharmaflow-django-asg \
  --min-size 0 \
  --desired-capacity 0

echo "Django ASG 종료 요청 완료"
