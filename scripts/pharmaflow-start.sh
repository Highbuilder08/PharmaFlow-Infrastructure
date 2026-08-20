#!/bin/bash
set -e

echo "=== PharmaFlow 업무 시작 ==="

echo "[1/1] Django ASG 시작: 0 -> 2"

aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name pharmaflow-django-asg \
  --min-size 0 \
  --desired-capacity 2

echo "Django ASG 시작 요청 완료"

