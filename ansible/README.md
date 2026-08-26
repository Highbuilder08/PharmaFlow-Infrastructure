# PharmaFlow Ansible

Terraform이 만든 EC2 **안을 채우는** 단계입니다.
(Terraform = 서버 생성 / Ansible = 서버 구성. 서로 자동 연동되지 않고 사람이 IP를 넘겨줍니다.)

## 접속 경로

Nginx / Django EC2는 Private Subnet에 있고 공인 IP가 없습니다.
관리 트래픽은 전부 Bastion을 경유합니다.

```
Server1 (Ansible)
   ↓ SSH
Bastion (Public A)
   ↓ SSH (ProxyJump)
Django (Private A) / Nginx (Private A)
```

Bastion 경유(ProxyCommand)는 인벤토리가 아니라 **`~/.ssh/config` 에서 관리합니다.**
`inventory/prod.ini` 하단의 주석 샘플을 실행 서버의 `~/.ssh/config` 에 채워 넣으세요.
인벤토리에는 대상 서버 사설 IP만 남습니다.

## 구조

```
ansible/
├── ansible.cfg                 기본 설정
├── inventory/prod.ini          대상 서버 목록  ← EC2 생성 후 IP 교체 필요
├── group_vars/
│   └── all/                    ⚠️ 폴더 이름 = 그룹 이름. 반드시 all/ 아래에 둘 것
│       ├── vars.yml            공통 변수 (비밀값 아님)
│       └── vault.yml.example   비밀값 템플릿
├── django.yml                    배포 지휘서
└── roles/
    ├── django/                 팀원2 담당
    └── nginx/                  팀원3 담당 (예정)
```

> `group_vars/vault.yml` 처럼 `all/` 밖에 두면 `vault` 라는 그룹이 없어서
> 파일이 통째로 무시됩니다. 로드 여부는 `ansible-inventory --host django-01` 로 확인하세요.

## 최초 1회 준비

> ⚠️ **`git pull` 만으로는 실행되지 않습니다.**
> 아래 3개는 전부 `.gitignore` 로 차단되어 있어 저장소에 없습니다.
> 플레이북을 실행하는 서버(Server1)에서 **최초 1회 직접 만들어야** 합니다.
>
> | 파일 | 없으면 |
> |---|---|
> | `group_vars/all/vault.yml` | `.env` 배포 단계에서 `django_db_password is undefined` |
> | `group_vars/all/local.yml` | 사설 IP·RDS·EFS 값이 없어 assert 또는 undefined 로 실패 |
> | `inventory/prod.local.ini` | 대상 호스트가 없어 ping 부터 실패 |
> | `~/.ssh/pharmaflow-infra-key.pem` | SSH 인증 실패 |
>
> 실제 환경 값(사설 IP, RDS 엔드포인트, EFS DNS)은 전부 **`local.yml` 한 곳**에 둡니다.
> 예전 방식(`prod.local.ini` 의 `[all:vars]`)과 혼용하지 마세요 — `group_vars` 가
> 인벤토리 변수보다 우선이라, 양쪽 값이 다르면 `local.yml` 이 조용히 이깁니다.

```bash
cd ansible

# 1) 비밀값 파일 생성
cp group_vars/all/vault.yml.example group_vars/all/vault.yml
vi group_vars/all/vault.yml                    # DB 비밀번호, HIRA 키, (SES 발급 후) SMTP 자격증명
ansible-vault encrypt group_vars/all/vault.yml # 암호화

# 2) EC2 접속 키 배치 (팀장님께 pharmaflow-infra-key.pem 을 안전한 경로로 받으세요)
cp <받은키>.pem ~/.ssh/pharmaflow-infra-key.pem
chmod 600 ~/.ssh/pharmaflow-infra-key.pem

# 3) 인벤토리 로컬 사본 생성 (대상 서버 사설 IP)
cp inventory/prod.ini inventory/prod.local.ini
vi inventory/prod.local.ini                    # ansible_host 만 실제 값으로

# 4) 실제 환경 값 파일 생성 (사설 IP, RDS 엔드포인트, EFS DNS)
cp group_vars/all/local.yml.example group_vars/all/local.yml
vi group_vars/all/local.yml

# 5) Bastion 경유 설정 (~/.ssh/config)
#    prod.ini 하단의 주석 샘플대로 채웁니다. Bastion 공인 IP는 여기에만 들어갑니다.
vi ~/.ssh/config
```

> 🔒 **이 저장소는 Public 입니다. 실제 IP를 커밋하지 마세요.**
> `inventory/prod.local.ini` 는 `.gitignore` 로 차단되어 있습니다.
> 아래 명령은 전부 `-i inventory/prod.local.ini` 를 붙여서 실행합니다.
> (매번 붙이기 번거로우면 `export ANSIBLE_INVENTORY=inventory/prod.local.ini`)

> 🔑 **Bastion 에 .pem 을 올리지 마세요.**
> ProxyCommand 는 `-W` 옵션으로 Bastion 을 순수 터널로만 씁니다.
> 개인키는 이 PC 에만 있으면 되고, Bastion 이 털려도 Private 서버 키까지 같이 넘어가지 않습니다.
> 이미 올려둔 `.pem` 이 있다면 지우세요.
>
> ```bash
> ssh -i ~/.ssh/pharmaflow-infra-key.pem ubuntu@<BASTION-PUBLIC-IP> \
>     'shred -u ~/pharmaflow-infra-key.pem'
> ```

## EC2 생성 후

```bash
# 1) 실제 IP 확인
cd ../environments/prod && terraform output && cd ../../ansible

# 2) IP 교체 (3곳) — 공인 IP는 커밋되지 않는 곳에만 적습니다
#    - inventory/prod.local.ini  의 ansible_host (사설 IP)
#    - ~/.ssh/config             의 Bastion HostName (공인 IP)
#    - group_vars/all/vars.yml   의 *_private_ip
#      (vars.yml 은 커밋되므로 사설 IP만. 공인 IP는 절대 넣지 마세요)

# 3) 호스트 키 등록 (첫 접속 질문 방지)
#    Bastion 은 직접, Private 서버는 Bastion 을 거쳐서 등록합니다.
ssh-keyscan -H <BASTION-PUBLIC-IP> >> ~/.ssh/known_hosts
ssh -J ubuntu@<BASTION-PUBLIC-IP> ubuntu@<DJANGO-PRIVATE-IP> exit   # 여기서 yes 한 번

# 4) 접속 확인
ansible -i inventory/prod.local.ini django -m ping

# 5) 예행연습 - 실제로 바꾸지 않고 뭐가 바뀔지만 확인
ansible-playbook -i inventory/prod.local.ini django.yml \
    --limit django --ask-vault-pass --check --diff --skip-tags db

# 6) 실제 적용  ← 아래 "실행 시나리오" 를 먼저 읽으세요
ansible-playbook -i inventory/prod.local.ini django.yml \
    --limit django --ask-vault-pass --skip-tags db
```

## 실행 시나리오 (RDS 전 / 후)

`roles/django/defaults/main.yml` 의 `django_db_host` / `django_efs_dns` 는
일부러 `REPLACE-WITH-...` 플레이스홀더로 커밋되어 있습니다 (아래 🔒 참고).
실제 값을 `group_vars/all/local.yml` 에 넣기 **전에** 전체 실행하면 반드시 실패합니다.
그래서 role 을 태그로 끊어두었습니다.

| 태그 | 내용 |
|---|---|
| `packages` | OS 패키지 설치 |
| `app` | 소스 clone + venv/의존성 |
| `config` | 디렉터리·SECRET_KEY·`.env`·systemd 유닛·logrotate |
| `storage` | media 공유 스토리지 마운트 (EFS/NFS) |
| `db` | migrate / collectstatic ← **RDS 엔드포인트 필요** |
| `service` | 서비스 활성화·기동 |

### ① 엔드포인트 주입 전 — 기본 구성까지

```bash
ansible-playbook -i inventory/prod.local.ini django.yml \
    --limit django --ask-vault-pass --skip-tags db
```

여기까지 통과하면 정상입니다. 이 상태에서는:

- `systemctl status pharmaflow` 가 **active** 여야 합니다
  (Django 는 기동 시점에 DB 에 연결하지 않으므로 RDS 없이도 뜹니다)
- DB 를 건드리는 페이지는 **500** 이 납니다. 이 단계에서는 정상입니다
- `.env` 의 `DB_HOST` 는 아직 플레이스홀더입니다

### ② 엔드포인트 주입 후 — 마이그레이션까지

RDS 엔드포인트와 EFS DNS 는 **커밋하지 않습니다.**
`group_vars/all/local.yml` 에 넣어 role defaults 를 덮어씁니다 (`local.yml.example` 참고).

```yaml
django_db_host: <RDS 엔드포인트>
efs_dns: <EFS DNS 이름>        # django/nginx role 공용
```

> 🔒 **왜 커밋하지 않나**
> 이 값들은 전 세계에서 resolve 되는 AWS 리소스 식별자입니다. 저장소가 Public 이고
> VPC CIDR·서브넷·SG 규칙이 이미 공개돼 있어서, 여기에 실제 주소까지 더하면
> 내부 구성이 그대로 드러납니다. 한번 커밋하면 나중에 지워도 히스토리에 남습니다.
>
> `defaults/main.yml` 은 `REPLACE-WITH-...` 플레이스홀더로 유지하세요.
> 반영이 됐는지는 이렇게 확인합니다:
>
> ```bash
> ansible-inventory -i inventory/prod.local.ini --host django-01 | grep db_host
> ```

```bash
# 마이그레이션만 추가로
ansible-playbook -i inventory/prod.local.ini django.yml \
    --limit django --ask-vault-pass --tags db

# 또는 전체
ansible-playbook -i inventory/prod.local.ini django.yml \
    --limit django --ask-vault-pass
```

교체 전에 `db` 를 돌리면 `assert` 가 먼저 잡아서, DB 연결 타임아웃 대신
"아직 플레이스홀더입니다" 라는 메시지로 즉시 멈춥니다.

> 급하게 한 번만 확인하고 싶다면 커밋 없이 `-e` 로 넘길 수도 있습니다.
> 다만 이렇게 하면 엔드포인트가 저장소에 남지 않으므로, 검증용으로만 쓰고
> 확정 값은 반드시 위 경로로 커밋하세요.
>
> ```bash
> ansible-playbook -i inventory/prod.local.ini django.yml \
>     --limit django --ask-vault-pass --tags db \
>     -e django_db_host=<RDS-엔드포인트>
> ```

실행에 실패하면 아래 "지뢰 3개" 를 먼저 확인하세요.

## EC2 없이 지금 할 수 있는 검증

```bash
ansible-playbook django.yml --syntax-check   # 문법 검사 (접속 안 함)
ansible-inventory --graph                  # 인벤토리 확인
ansible-inventory --host django-01         # 변수가 실제로 로드되는지 확인
```

## django role 이 하는 일

| 순서 | 내용 |
|---|---|
| 1 | 빌드/런타임 apt 패키지 설치 |
| 2 | PharmaFlow 소스 clone ← **디렉터리 생성보다 먼저** |
| 3 | 앱 디렉터리 권한 정리 |
| 4 | venv 생성 + requirements.txt 설치 |
| 5 | SECRET_KEY 생성 (최초 1회만) |
| 6 | `.env` 배포 |
| 7 | `pharmaflow.service` systemd 유닛 배포 |
| 8 | EFS/NFS media 마운트 (선택) |
| 9 | migrate + collectstatic ← **environment 로 환경변수 주입 필수** |
| 10 | logrotate 설정 배치 (템플릿) |
| 11 | 서비스 활성화·시작 |

근거: 앱 저장소의 `deploy/manual/운영매뉴얼.md`, `deploy/SECURITY_AND_SETUP.md`

### 이 role 을 고칠 때 밟기 쉬운 지뢰 3개

1. **2번이 3번보다 먼저여야 합니다.** `git clone` 은 대상 디렉터리가 비어 있어야 성공합니다.
   `media/` 를 먼저 만들면 `destination path already exists and is not an empty directory` 로 죽습니다.
2. **9번에는 `environment:` 가 필요합니다.** `.env` 는 systemd 의 `EnvironmentFile` 로만 읽힙니다.
   Ansible `command` 는 그 파일을 모르므로, 없으면 `settings.py` 가
   `RuntimeError: DJANGO_SECRET_KEY 환경변수가 필요합니다` 로 즉시 죽습니다.
3. **`LOG_LEVEL` 은 대문자여야 합니다.** gunicorn 은 `.lower()` 해서 쓰지만
   Django `LOGGING` 은 그대로 파이썬 로깅 레벨로 넘깁니다.
   소문자 `info` 를 넣으면 `ValueError: Unable to configure root logger` 로 앱이 아예 안 뜹니다.

## 현재 3-Tier Nginx 연동 구조

기존의 Nginx → Django Base EC2 직접 연결 구조는 종료되었으며,
현재는 Nginx와 Django 모두 Auto Scaling Group 기반의 3-Tier 구조를 사용합니다.

현재 서비스 요청 흐름은 다음과 같습니다.

```
Internet
  ↓
Public ALB
  ↓
Nginx ASG (Web Private A/C)
  ↓
Internal ALB :80
  ↓
Django ASG :8000
```

Nginx는 더 이상 Django Base EC2의 사설 IP를 직접 참조하지 않습니다.

Nginx role의 backend 설정은 다음과 같습니다.

```yaml
nginx_backend_host: "{{ internal_alb_dns }}"
nginx_backend_port: 80
```

실제 Internal ALB DNS 값은 Public Git 저장소에 커밋하지 않고
`group_vars/all/local.yml`에서 환경별로 관리합니다.

`group_vars/all/local.yml.example`에는 실제 DNS 대신 placeholder만 유지합니다.

```yaml
internal_alb_dns: "REPLACE-WITH-INTERNAL-ALB-DNS"
```

Nginx 설정 템플릿은 변수 기반 구조를 유지합니다.

```nginx
proxy_pass http://{{ nginx_backend_host }}:{{ nginx_backend_port }};
```

따라서 Nginx에서 Django까지의 요청 흐름은 다음과 같습니다.

```text
Nginx ASG
  ↓ HTTP :80
Internal ALB
  ↓ HTTP :8000
Django ASG
```

Django ASG의 Gunicorn은 `0.0.0.0:8000`에 바인딩되며,
Django Security Group의 8000 포트는 Internal ALB Security Group에서만
접근할 수 있도록 제한합니다.

## Golden AMI 파이프라인 — role 을 고치면 여기까지 해야 반영됩니다

ASG 인스턴스는 **AMI 에 구워진 상태 그대로** 뜹니다. Launch Template 에 user_data 가
없으므로 부팅 시 아무것도 실행되지 않고, Ansible 이 다시 돌지도 않습니다.

```
django role 수정
   ↓  ansible-playbook (base EC2 에 재적용)
Django Base EC2
   ↓  terraform (aws_ami_from_instance 새 버전, 예: v3)
Golden AMI
   ↓  terraform (launch_template image_id 갱신)
Launch Template
   ↓  인스턴스 교체 (instance refresh 또는 desired 0→N)
ASG 인스턴스
```

> ⚠️ **base EC2 를 손으로 고치지 마세요.**
> 손수정은 ① 다음 Ansible 실행이 덮어쓰고 ② 그 전에 AMI 를 구우면 코드에 없는
> 상태가 ASG 전체로 복제됩니다. golden AMI v1→v2 교체가 바로 이 사례입니다
> (`.env` 의 ALLOWED_HOSTS 수동 변경 → v2 재베이크). 지금은 그 결정이
> `vars.yml` 의 `django_allowed_hosts: ["*"]` 로 코드에 회수되어 있으므로,
> **base EC2 재적용 → 재베이크를 해도 같은 상태가 재현됩니다.**

참고: AMI 에는 `.env`(DB 비밀번호 포함)와 `.secret_key` 가 그대로 들어갑니다.
ASG 인스턴스들이 SECRET_KEY 를 공유하는 것은 의도된 동작입니다(세션·서명 호환).

## ASG 배포 후 재검증 체크리스트 (Server1 에서)

ASG 인스턴스 IP 는 매번 바뀌므로 먼저 IP 를 확인합니다. 태그로 조회:

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=pharmaflow-django-asg" \
            "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].PrivateIpAddress" --output text
```

각 인스턴스에 Bastion 경유로 접속해서 (`ssh <사설IP>` — ~/.ssh/config 가 처리):

| 항목 | 명령 | 기대 결과 |
|---|---|---|
| 서비스 | `systemctl is-active pharmaflow` | `active` |
| Gunicorn 바인딩 | `ss -ltn 'sport = :8000'` | `0.0.0.0:8000` LISTEN |
| EFS 마운트 | `findmnt ~ubuntu/djangowork/PharmaFlow/media` | nfs4, EFS DNS 표시 |
| RDS 연결 | `cd ~/djangowork/PharmaFlow && (set -a; . ./.env; set +a; ~/djangoenv/bin/python manage.py check --database default)` | `System check identified no issues` |
| 응답 확인 | `curl -s -o /dev/null -w '%{http_code}' localhost:8000/` | 200 또는 302 |
| Django 로그 | `journalctl -u pharmaflow -n 50 --no-pager` | Traceback/ERROR 없음, gunicorn 워커 기동 로그 |

Target 상태는 인스턴스 밖에서:

```bash
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups \
      --names pharmaflow-django-tg --query 'TargetGroups[0].TargetGroupArn' --output text) \
  --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State]' --output table
```

전부 `healthy` 면 Django 서비스 인프라 검증 완료입니다.

## 팀 확인이 필요한 미확정 사항

| 항목 | 상태 |
|---|---|
| **RDS 엔드포인트 / EFS DNS** | ~~미확정~~ → **생성 완료.** Public 저장소라 실제 값은 커밋하지 않고 `group_vars/all/local.yml` 로 주입합니다 (위 "실행 시나리오 ②"). `defaults/main.yml` 의 플레이스홀더는 의도된 것이니 교체하지 마세요 |
| **ALB Health Check 경로** | ~~미확정~~ → **해소.** `internal_alb.tf` 가 `path=/`, `matcher=200-399` 로 302 리다이렉트를 정상으로 판정합니다. 앱에 `/health` 뷰가 생기면 `path=/health`, `matcher=200` 으로 좁히는 게 더 정확합니다 (선택) |
| **ASG 확장 시 ALLOWED_HOSTS** | ~~미확정~~ → **해소(트레이드오프).** `django_allowed_hosts: ["*"]` 채택. ALB 헬스체크가 Host 헤더에 매번 바뀌는 인스턴스 IP를 넣기 때문입니다. Host 헤더 검증을 포기하는 대신 Private Subnet + SG(Internal ALB→8000만 허용)로 접근 자체를 격리합니다. 앱에 `/health` 뷰가 생기면 목록 방식으로 되돌릴 수 있습니다 |
| **Static 파일 공유 구조** | **구현 완료.** Django `collectstatic` 결과를 공용 EFS의 `/srv/pharmaflow/static/staticfiles`에 저장하고, Nginx ASG가 동일한 EFS를 마운트하여 `/static/` 요청을 직접 제공합니다. Django와 Nginx가 서로 다른 ASG 인스턴스로 동작하므로 로컬 staticfiles 디렉터리를 공유할 수 없는 문제를 EFS로 해결했습니다. S3 + CloudFront 방식은 현재 사용하지 않습니다. |

## Nginx ASG 장애 / 복구 테스트 절차

Nginx ASG 장애 발생 시 서비스 지속 및 Auto Scaling 자동 복구 여부를
검증하기 위한 절차입니다.

> 이 절차는 실제 장애/복구 검증 시 사용하기 위한 문서입니다.
> README 현행화 작업에서는 실제 인스턴스 종료, ASG 조작 또는
> `terraform apply`를 수행하지 않습니다.

### 1. Nginx ASG 정상 상태 확인

Nginx ASG에서 실행 중인 인스턴스와 Availability Zone을 확인합니다.

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=pharmaflow-nginx-asg" \
            "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].[InstanceId,State.Name,Placement.AvailabilityZone]" \
  --output table
```

기대 결과:

- 실행 중인 Nginx 인스턴스 2대
- `ap-northeast-2a` / `ap-northeast-2c`에 분산 배치

### 2. Nginx Target Group 상태 확인

```bash
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups \
      --names pharmaflow-nginx-tg \
      --query 'TargetGroups[0].TargetGroupArn' \
      --output text) \
  --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State]' \
  --output table
```

기대 결과:

- Nginx 인스턴스 2대 모두 `healthy`
- Target Group `2/2 healthy`

### 3. 장애 발생 전 외부 서비스 확인

```bash
curl -I https://pharmaflow.homes
```

기대 결과:

- HTTPS 요청 정상 응답
- 현재 확인 기준 `HTTP/2 200`

### 4. Nginx 인스턴스 1대 장애 테스트

검증 담당자가 Nginx ASG 인스턴스 중 1대를 종료하여 장애 상황을 발생시킵니다.

장애 발생 직후에도 외부 서비스가 계속 응답하는지 확인합니다.

```bash
curl -I https://pharmaflow.homes
```

기대 결과:

- 남아 있는 정상 Nginx 인스턴스를 통해 서비스 지속
- HTTPS 요청 정상 응답

### 5. ASG 신규 인스턴스 자동 생성 확인

Nginx ASG가 `desired_capacity = 2`를 유지하기 위해
신규 인스턴스를 자동 생성하는지 확인합니다.

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=pharmaflow-nginx-asg" \
            "Name=instance-state-name,Values=pending,running" \
  --query "Reservations[].Instances[].[InstanceId,State.Name,Placement.AvailabilityZone]" \
  --output table
```

기대 결과:

- 장애 인스턴스를 대체할 신규 인스턴스 자동 생성
- 최종적으로 실행 중인 Nginx 인스턴스 2대 복구

### 6. 신규 인스턴스 Target Group 등록 확인

```bash
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups \
      --names pharmaflow-nginx-tg \
      --query 'TargetGroups[0].TargetGroupArn' \
      --output text) \
  --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State]' \
  --output table
```

신규 인스턴스의 Target Health 상태가 다음과 같이 변경되는지 확인합니다.

```text
initial
  ↓
healthy
```

최종적으로 Target Group이 다시 `2/2 healthy` 상태가 되어야 합니다.

### 7. Multi-AZ 분산 상태 확인

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=pharmaflow-nginx-asg" \
            "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].[InstanceId,Placement.AvailabilityZone]" \
  --output table
```

기대 결과:

- `ap-northeast-2a`
- `ap-northeast-2c`

두 Availability Zone에 Nginx 인스턴스가 정상 분산되어 있어야 합니다.

### 8. 장애 복구 후 최종 서비스 확인

```bash
curl -I https://pharmaflow.homes
```

최종 확인 항목:

- 외부 HTTPS 요청 정상 응답
- Nginx ASG 인스턴스 2대 정상
- Nginx Target Group `2/2 healthy`
- Web Private A/C Multi-AZ 분산 정상
- 신규 인스턴스가 Target Group에서 `healthy` 상태

장애/복구 테스트 완료 후 서비스와 ASG/Target Group이
초기 정상 상태로 복구되었는지 최종 확인합니다.

## 주의

- `group_vars/all/vault.yml` 은 절대 커밋하지 마세요 (`.gitignore` 로 차단되어 있음)
- `*.pem` 키 파일도 마찬가지입니다
- `host_key_checking` 을 끄지 마세요. 대신 `ssh-keyscan` / `ssh -J` 로 키를 등록합니다
- AMI는 **Ubuntu 24.04 (Noble)** 전제입니다. Django 6.0이 Python 3.12+ 를 요구합니다
