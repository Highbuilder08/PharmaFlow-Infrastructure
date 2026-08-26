# Django Application Tier — 최종 정리 (발표·검증용)

작성: Django 담당 / 기준: 2026-08-26 main
각 항목을 **기존 문제 → 개선 방법 → 적용 기술 → 검증 결과** 순서로 정리한다.

## 요약 — 한눈에

```
[기존]                              [현재]
Django Base EC2 1대                 Django ASG 2대 (App Private A/C, Multi-AZ)
고정 사설 IP 의존                    Internal ALB 경유 (IP 무관)
수동 설치·설정                       Golden AMI v5 + Launch Template
"/" 단일 헬스체크 (DB 혼재)          /health/live/ + /health/ready/ 분리
설정 하드코딩 (Gmail, static 경로)   전부 환경변수 (.env) 주입
로컬 staticfiles                    EFS 공유 + Nginx 직접 서빙
```

## 1. Django ASG / Multi-AZ

| | |
|---|---|
| 기존 문제 | Django 1대(Base EC2). 인스턴스 장애 = 서비스 중단(단일 장애 지점). AZ 장애에도 무방비. 이용량 변화에 수동 대응 |
| 개선 방법 | 같은 상태의 인스턴스를 여러 AZ에 복수 배치하고, 장애 시 자동 교체·부하 시 확장 가능한 구조로 전환 |
| 적용 기술 | ASG `min 0 / desired 2 / max 4`, `vpc_zone_identifier` = App 전용 Private A/C(2a·2c). Internal ALB Target Group에 자동 등록. `health_check_type=ELB`, grace 180s |
| 검증 결과 | Django TG 2/2 healthy, 인스턴스가 2a·2c에 분산 배치됨을 확인. Rolling Instance Refresh로 무중단 교체 동작. **인스턴스 강제 종료 시 자동 복구는 오늘(8/26) 통합 장애시험에서 기록** |

## 2. Golden AMI

| | |
|---|---|
| 기존 문제 | 서버를 늘릴 때마다 수동 설치 반복 → 서버별 설정 편차(snowflake). Base EC2를 손으로 고치면 ASG 인스턴스에는 반영되지 않거나, 반대로 코드에 없는 상태가 AMI로 전체 복제됨 |
| 개선 방법 | "서버를 고치지 않고 이미지를 교체한다" — 수정은 Ansible 코드로만, 반영은 이미지 재베이크로만 하는 불변(immutable) 파이프라인 |
| 적용 기술 | Base EC2 → Ansible 적용 → 검증 → `aws_ami_from_instance`(버전 유지: v1~v5) → Launch Template `image_id` 갱신 → ASG Rolling Instance Refresh. 현재 Django Golden AMI **v5**(Shared Static 반영), Launch Template **Version 5**가 v5 AMI 참조 |
| 검증 결과 | v1(초기) → v2(ALLOWED_HOSTS 코드 회수) → v3 → v4(liveness/readiness) → v5(Shared Static, 2026-08-26) 이력으로 "코드 수정 → 재베이크 → 전체 반영" 사이클 반복 검증. 이전 버전 AMI가 남아 있어 롤백 가능 |

## 3. /health/live/ · /health/ready/ 분리 이유

| | |
|---|---|
| 기존 문제 | 헬스체크가 `/`(메인 화면) 하나였고, 이 페이지는 DB를 조회한다. 그래서 **"Django가 죽었다"와 "DB가 죽었다"를 구분할 수 없었다.** RDS 장애·Failover 순단 중에는 멀쩡한 Django 인스턴스까지 unhealthy로 판정 → ASG(ELB 타입)가 정상 인스턴스를 계속 교체하는 악순환 가능 |
| 개선 방법 | 판정 목적별로 신호를 분리한다. "인스턴스를 교체하면 나아지는가?"(liveness)와 "지금 트래픽을 보내도 되는가?"(readiness)는 다른 질문이다 |
| 적용 기술 | 앱 PR #78·#79: `/health/live/`(프로세스만, DB 조회 없음, 항상 200) / `/health/ready/`(`SELECT 1`, 정상 200·DB 장애 503) / `/health/`(readiness 호환 별칭). 인증 불필요, 읽기 전용, `never_cache` |
| 검증 결과 | 테스트 9건(쿼리 0건 검증 `assertNumQueries(0)` 포함 — live에 DB 코드가 들어오면 테스트가 깨짐). runserver 실측: live 200 / ready 200 / DB 다운 mock 시 ready만 503. 실서버: 두 endpoint 모두 200 확인 |

## 4. Target Group /health/live/ 정책

| | |
|---|---|
| 기존 문제 | TG `path=/, matcher=200-399`. ①로그인 리다이렉트(302)에 의존하는 넓은 matcher ②`/`가 DB 의존이라 DB 장애가 인스턴스 교체 루프로 번지는 구조(3번과 동일 원인) ③반대로 302는 DB가 죽어도 나올 수 있어 거짓 양성도 가능 |
| 개선 방법 | TG는 "인스턴스 교체 판단"에 맞는 신호(liveness)만 보게 하고, DB 상태는 별도 경로로 관측 |
| 적용 기술 | `path=/health/live/`, `matcher=200` (PR #27). DB 상태는 `/health/ready/`로 운영자·향후 모니터링이 별도 확인. 경로는 끝 슬래시 포함 필수(없으면 `APPEND_SLASH` 301 → unhealthy 오판정, 실측으로 확인) |
| 검증 결과 | 전환 후 TG 2/2 healthy 유지, 메인 HTTPS 200. **RDS Failover 중 "live 200 유지 + 인스턴스 교체 없음"은 오늘 통합 장애시험의 핵심 관측 항목** (절차: `docs/failover-verification.md`) |

## 5. RDS 연동 및 Multi-AZ Failover와의 관계

| | |
|---|---|
| 기존 문제 | ①DB가 단일 인스턴스(단일 장애 지점) ②앱이 DB 순단에 어떻게 반응하는지 정의되지 않음 ③보존 중인 구 RDS(pharmaflow-db)를 Failover 수단으로 오해할 여지 |
| 개선 방법 | DB 고가용성은 RDS Multi-AZ(AWS 관리 Standby + 자동 Failover)로 확보하고, 앱은 "순단 후 자동 회복"이 되는 연결 방식을 확인해 둔다 |
| 적용 기술 | `pharmaflow-db-tier` `multi_az=true` (PR #28). 앱 연결: `DB_HOST` 환경변수(RDS DNS) + `CONN_MAX_AGE` 미설정(=0, 요청마다 새 커넥션) → Failover로 DNS가 Standby를 가리키면 **재시작 없이** 새 요청부터 자동 회복. 구 RDS는 stopped 롤백용일 뿐 Standby가 아님을 문서에 명시 |
| 검증 결과 | Failover 중 예상 신호를 사전 정의: live 200 유지 / ready 503(순단 60~120초) / 복구 후 ready 200 자동 회복. **실측은 오늘 장애시험에서 기록** — 시나리오·관측 루프·판정 기준은 `docs/failover-verification.md`에 준비 완료 |

## 6. Email — EMAIL_* 환경변수화

| | |
|---|---|
| 기존 문제 | 설정 기본값과 예제가 Gmail에 종속(`smtp.gmail.com` 하드 기본값, "Google 앱 비밀번호" 안내). `@pharmaflow.homes` 메일 인프라(SES 등)가 확정되면 코드 수정이 필요한 구조 |
| 개선 방법 | 어떤 SMTP 서비스로 결정되든 코드 변경 없이 값만 갈아끼우면 되도록 서비스 중립화 |
| 적용 기술 | 앱 PR #80: `EMAIL_HOST` 기본값 중립화(`localhost`), `EMAIL_BACKEND/HOST/PORT/USE_TLS/USE_SSL/HOST_USER/HOST_PASSWORD/DEFAULT_FROM_EMAIL` 전부 env 주입, `.env.example`에 Gmail/SES 예시 병기. 자격증명은 Git 제외. 사용처 2곳(회원가입 인증번호, 비밀번호 재설정)은 실패 시 로깅+사용자 안내 처리 |
| 검증 결과 | 발송 테스트 3건(인증번호/재설정/발신자 주소가 설정을 따르는지) 통과. `DEFAULT_FROM_EMAIL`의 `noreply@pharmaflow.homes` 전환은 메일 인프라 문서(PR #31)의 SPF/DKIM 적용 이후 — 그 전 사용 시 스팸 처리 위험을 명시 |

## 7. STATIC_ROOT 환경변수화 및 Shared Static 구조

| | |
|---|---|
| 기존 문제 | `STATIC_ROOT`가 `BASE_DIR/staticfiles` 하드코딩. ASG 다중 인스턴스에서는 각자 로컬에 collectstatic → 인스턴스마다 정적 파일이 따로 놀고, Nginx가 직접 서빙할 방법도 없음 |
| 개선 방법 | collectstatic 산출 위치를 배포 환경이 결정하게 하고(환경변수), 그 위치를 공유 스토리지로 두어 Web Tier(Nginx)가 동일 파일을 직접 서빙 |
| 적용 기술 | 앱 PR #81: `STATIC_ROOT = Path(os.environ.get("STATIC_ROOT", BASE_DIR/"staticfiles"))` (LOG_DIR과 동일 패턴, 미설정 시 동작 불변). 인프라 PR #32: EFS를 `/srv/pharmaflow/static`에 마운트 → `env.j2`가 `STATIC_ROOT=/srv/pharmaflow/static/staticfiles` 주입 → collectstatic이 EFS에 산출 → Nginx `location /static/ { alias ... }`가 같은 EFS를 직접 서빙 |
| 검증 결과 | 앱: override 경로로 collectstatic 실행, 134개 파일이 지정 경로에 복사됨 확인 + 기존 테스트 통과. 인프라: Nginx가 `/static/` 요청을 Django를 거치지 않고 EFS에서 직접 응답(앱 부하 제거). **ASG 신규 인스턴스에서도 동일 정적 파일이 보이는지는 오늘 장애시험에서 확인 항목** |

## 오늘(8/26) 통합 장애시험 — Django 담당 기록 항목

실험 조작은 통합 담당이 수행하고, Django 담당은 아래를 관측·기록한다.
(관측 명령 상세: `docs/failover-verification.md`, `ansible/README.md` 재검증 체크리스트)

| 시험 | 기록할 것 | 기대 |
|---|---|---|
| Django 인스턴스 강제 종료 | TG 상태 변화, ASG 대체 인스턴스 생성 시각, 서비스 응답 | 자동 복구, 서비스 무중단(1대 잔존) |
| RDS Multi-AZ Failover | live/ready 코드 추이(관측 루프), AZ 스왑, ready 자동 회복, **인스턴스 교체 발생 여부** | live 내내 200, ready 503→200, 교체 0건 |
| 신규 인스턴스 검증 | `systemctl is-active` / live·ready / EFS(media·static) 마운트 / `/static/` 응답 | 체크리스트 전 항목 통과 |

문제 발견 시: Django 담당이 앱/role 수정 → PR (오늘 대기 상태 유지).
