# RDS 장애 / Health Check 검증 절차

RDS Multi-AZ Failover 테스트에서 사용할 검증 절차입니다.
이 문서는 **절차만** 정의합니다. RDS 중지/Failover, Terraform Apply 등
실제 AWS 변경은 문서 범위가 아니며, 실행 주체는 각 단계에 표기했습니다.

## 검증 대상 endpoint (앱 PR #78, #79)

| 경로 | 확인 범위 | 정상 | DB 장애 시 |
|---|---|---|---|
| `/health/live/` | Django 프로세스만 (DB 조회 없음) | 200 `alive` | **200 유지** |
| `/health/ready/` | Django + DB (`SELECT 1`) | 200 `healthy` | **503** `unhealthy` |
| `/health/` | readiness 별칭 | 200 | 503 |

## 작성 시점 전제 (2026-08-25) — 테스트 전 반드시 재확인

| 항목 | 현재 상태 | 영향 |
|---|---|---|
| Golden AMI | v4 (health endpoint 포함) 배포됨 | live/ready 검증 가능 |
| Django TG 헬스체크 | 아직 `path=/`, `matcher=200-399` | 아래 ⚠️ 참고 |
| ASG `health_check_type` | **ELB** (grace 180s) | 아래 ⚠️ 참고 |
| RDS `multi_az` | **false** | Failover 테스트 전 Multi-AZ 전환 선행 필요 (팀장) |
| 앱 `CONN_MAX_AGE` | 미설정 = 0 (요청마다 새 커넥션) | Failover 후 ready 자동 복구 기대 가능 |

> ⚠️ **DB 장애 시 ASG 교체 루프 위험 (테스트 전 팀장 결정 필요)**
>
> 현행 TG 경로 `/` 는 메인 화면(index)이라 DB 를 조회합니다. DB 장애 시
> `/` 는 500 → Target unhealthy → `health_check_type=ELB` 이므로 **ASG 가
> 인스턴스를 교체하기 시작합니다.** DB 장애는 인스턴스 교체로 낫지 않으므로
> 교체 루프가 됩니다. TG 를 `/health/ready/` 로 바꿔도 ELB 타입인 한 동일합니다.
>
> unhealthy 판정까지 약 60초(interval 30s × unhealthy_threshold 2)이고 Multi-AZ
> failover 순단도 통상 60~120초라, **짧은 failover 에서도 교체가 발동할 수 있습니다.**
> 테스트 전 선택지:
> - **A. ASG 헬스체크 프로세스 일시 중단** (권장, 팀장 실행):
>   `aws autoscaling suspend-processes --auto-scaling-group-name <asg> --scaling-processes HealthCheck ReplaceUnhealthy`
>   → 테스트 후 `resume-processes` 로 복원
> - **B. 교체 발동을 감수하고 그 동작 자체를 관찰** — 이 경우 "교체된 새 인스턴스도
>   DB 가 죽어 있는 동안 unhealthy" 라는 루프를 확인하는 것이 관찰 목표가 됨

## 준비 (Server1)

```bash
# 값 확인 (실제 값은 커밋 금지 - 필요 시 local.yml/터미널에만)
cd environments/prod && terraform output

# ASG 인스턴스 사설 IP 조회
aws ec2 describe-instances \
  --filters "Name=tag:aws:autoscaling:groupName,Values=<django-asg-name>" \
            "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].PrivateIpAddress" --output text

# RDS 식별자 확인 (인스턴스가 2개면 실제 사용 중인 것은 .env 의 DB_HOST 기준)
aws rds describe-db-instances \
  --query "DBInstances[].[DBInstanceIdentifier,MultiAZ,AvailabilityZone,SecondaryAvailabilityZone]" \
  --output table
```

관측 루프 2개를 준비합니다.

```bash
# [루프1] ASG 인스턴스 내부 (bastion 경유 ssh 후) - live/ready 를 5초 간격 기록
while true; do echo "$(date '+%T') \
live=$(curl -s -o /dev/null -w '%{http_code}' localhost:8000/health/live/) \
ready=$(curl -s -o /dev/null -w '%{http_code}' localhost:8000/health/ready/)"; sleep 5; done

# [루프2] 외부 PC - HTTPS 서비스 관점
while true; do echo "$(date '+%T') \
https=$(curl -s -o /dev/null -w '%{http_code}' https://<도메인>/)"; sleep 5; done
```

## 1단계 — 정상 상태 기준선

| # | 확인 | 명령 (Server1 또는 표기 위치) | 기대 결과 |
|---|---|---|---|
| 1-1 | liveness | 인스턴스에서 `curl localhost:8000/health/live/` | 200 `{"status": "alive"}` |
| 1-2 | readiness | 인스턴스에서 `curl localhost:8000/health/ready/` | 200 `{"status": "healthy"}` |
| 1-3 | Target 상태 | `aws elbv2 describe-target-health --target-group-arn <django-tg-arn>` | 전부 `healthy` |
| 1-4 | HTTPS e2e | 외부에서 `curl -I https://<도메인>/` | 200 또는 302 |
| 1-5 | HTTP→HTTPS | 외부에서 `curl -I http://<도메인>/` | 301 → https |
| 1-6 | 인증서 | `echo \| openssl s_client -connect <도메인>:443 2>/dev/null \| openssl x509 -noout -dates` | 만료일이 충분히 남음 |
| 1-7 | RDS AZ 기록 | 위 `describe-db-instances` | 현재 AZ / Secondary AZ 메모 |

1-1~1-4 가 전부 정상일 때만 다음 단계로 진행합니다.

## 2단계 — DB 연결 장애 시 예상 결과

Failover 와 별개로, DB 연결 장애 상태의 각 신호를 미리 정의합니다.

| 신호 | DB 장애 중 예상 | 근거 |
|---|---|---|
| `/health/live/` | **200 유지** | DB 를 조회하지 않음 (앱 테스트 `assertNumQueries(0)` 로 고정) |
| `/health/ready/` | **503** | `SELECT 1` 실패 → `DatabaseError` |
| `/` (현행 TG 경로) | 500 | index 뷰가 DB 조회 |
| Django TG | unhealthy (약 60초 후) | `/` 500 은 matcher 200-399 밖 |
| HTTPS e2e | 502/503 (ALB 에러 페이지) | 라우팅할 healthy Target 없음 |
| Django 로그 | `OperationalError` | `journalctl -u pharmaflow` |

**live 가 503 이 되거나 ready 가 200 으로 남아 있으면 endpoint 구현 문제**이므로
테스트를 중단하고 앱 쪽을 먼저 확인합니다.

## 3단계 — RDS Multi-AZ Failover 전/중/후

### 전 (팀장 + Django 담당)

- [ ] `multi_az = true` 전환 완료, `describe-db-instances` 로 `MultiAZ: true` + Secondary AZ 확인
- [ ] 위 ⚠️ 의 ASG 프로세스 중단 여부 결정·실행 (A안이면 suspend 확인)
- [ ] 1단계 기준선 재확인 (전부 정상)
- [ ] 관측 루프1(인스턴스), 루프2(외부) 가동 + 화면 기록 시작
- [ ] Failover 유발 (팀장): `aws rds reboot-db-instance --db-instance-identifier <id> --force-failover`

### 중 (관측만, 개입 금지)

- [ ] 루프1: **live=200 이 끊기지 않고 유지** ← 이번 테스트의 핵심 확인
- [ ] 루프1: ready=503 구간 시작/종료 시각 기록 (예상 순단 60~120초)
- [ ] 루프2: HTTPS 응답 코드 변화 기록 (502/503 구간 = 사용자 영향 구간)
- [ ] `describe-target-health` 로 Target 상태 변화 기록

### 후 (Django 담당)

- [ ] `describe-db-instances`: AZ 와 Secondary AZ 가 **서로 바뀌었는지** 확인 (failover 증거)
- [ ] 루프1: ready=200 **자동 복구** 확인 (CONN_MAX_AGE=0 이므로 재시작 불필요가 기대값.
      503 이 지속되면 인스턴스 재시작 전에 `journalctl -u pharmaflow` 로 원인 먼저 수집)
- [ ] Target 전부 healthy 복귀 + ASG 인스턴스 교체가 없었는지(A안) 확인
- [ ] HTTPS e2e 200/302 복귀 + 로그인 등 DB 쓰는 화면 1개 수동 확인
- [ ] (A안이었다면) `aws autoscaling resume-processes ...` 로 복원 (팀장)
- [ ] 기록 정리: ready 503 구간 길이, HTTPS 영향 구간 길이, 교체 발생 여부

## 판정 요약

| 결과 | 판정 |
|---|---|
| live 내내 200 + ready 503→200 자동 복구 + AZ 스왑 확인 | **성공** |
| live 가 한 번이라도 200 아님 | endpoint 또는 프로세스 문제 - 앱 조사 |
| ready 503 지속 (복구 안 됨) | 커넥션/DNS 캐시 의심 - 로그 수집 후 판단 |
| ASG 가 인스턴스 교체 시작 (A안이었는데) | suspend 누락 여부 확인 |

## 참고

- TG 를 `/health/ready/` (`matcher=200`) 로 전환하면 2단계의 `/` 500 의존이 사라지고
  판정이 명확해집니다. 전환 시 경로는 **끝 슬래시 포함** (`/health/ready`) 는 301 이
  나와 unhealthy 로 판정됩니다 - 앱 PR #78 에서 실측).
- ASG 교체 판정과 트래픽 판정을 분리하려면 `health_check_type=EC2` 전환 또는
  liveness 전용 TG 구성이 필요합니다. `/health/live/` 는 이를 위해 준비된 endpoint 입니다.
