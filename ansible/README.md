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
> | `inventory/prod.local.ini` | 대상 호스트가 없어 ping 부터 실패 |
> | `~/.ssh/pharmaflow-infra-key.pem` | SSH 인증 실패 |
>
> `prod.local.ini` 에는 IP 뿐 아니라 **RDS 엔드포인트·EFS DNS 도 들어갑니다.**
> 이 값들은 커밋되지 않으므로 pull 로 오지 않습니다. 아래 "실행 시나리오 ②" 참고.

```bash
cd ansible

# 1) 비밀값 파일 생성
cp group_vars/all/vault.yml.example group_vars/all/vault.yml
vi group_vars/all/vault.yml                    # DB 비밀번호, HIRA 키 입력
ansible-vault encrypt group_vars/all/vault.yml # 암호화

# 2) EC2 접속 키 배치 (팀장님께 pharmaflow-infra-key.pem 을 안전한 경로로 받으세요)
cp <받은키>.pem ~/.ssh/pharmaflow-infra-key.pem
chmod 600 ~/.ssh/pharmaflow-infra-key.pem

# 3) 인벤토리 로컬 사본 생성 (실제 IP는 여기에만 적습니다)
cp inventory/prod.ini inventory/prod.local.ini
vi inventory/prod.local.ini                    # 서버 사설 IP + RDS/EFS 엔드포인트 입력

# 4) Bastion 경유 설정 (~/.ssh/config)
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
실제 값을 `prod.local.ini` 에 넣기 **전에** 전체 실행하면 반드시 실패합니다.
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
`inventory/prod.local.ini` 의 `[all:vars]` 에 넣어 role defaults 를 덮어씁니다.

```ini
[all:vars]
django_db_host=<RDS 엔드포인트>
django_efs_dns=<EFS DNS 이름>
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

> ⚠️ **이 role 은 아직 실서버에서 실행된 이력이 없습니다.**
> 지금까지 검증한 것은 `--syntax-check`, `--list-tasks`(태그 조합), 템플릿 렌더링뿐입니다.
> 최초 실행에서 실패하면 아래 "지뢰 3개" 를 먼저 확인하세요.

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

## 구축 단계 (Nginx 연동)

```
[초기 구축 단계]                    [최종 구축 단계]

Nginx                              Nginx ASG
  ↓                                  ↓
Django Base EC2                    Internal ALB
Private IP:8000                      ↓
                                   Django ASG

※ 기준 서버 동작 검증을 위한        ※ Internal ALB 구축 후
   임시 구성                          proxy_pass 를 Internal ALB DNS 로 변경
```

초기 단계에서 팀원3과 맞춰야 할 것:

- 이 role 은 Gunicorn 을 `0.0.0.0:8000` 에 바인딩합니다
  (앱 저장소 `gunicorn.conf.py` 기본값 `127.0.0.1:8000` 으로는 다른 EC2에서 접근 불가)
- 팀원3의 Nginx `proxy_pass` 는 `http://<Django Base EC2 사설 IP>:8000`
- Django SG는 8000 인바운드를 **Internal ALB SG에만** 허용합니다.
  Internal ALB가 없는 초기 단계용으로 `environments/prod/django.tf` 에
  Nginx SG → Django 8000 임시 규칙을 두었습니다. **Internal ALB 생성 후 삭제**하세요.

## 팀 확인이 필요한 미확정 사항

| 항목 | 상태 |
|---|---|
| **RDS 엔드포인트 / EFS DNS** | ~~미확정~~ → **생성 완료 (2026-08-20).** 단, Public 저장소라 실제 값은 커밋하지 않고 `prod.local.ini` 로 주입합니다 (위 "실행 시나리오 ②" 참고). `defaults/main.yml` 의 플레이스홀더는 의도된 것이니 교체하지 마세요 |
| **ALB Health Check 경로** | 앱에 전용 헬스체크 URL이 없습니다(`/health` 등). `/` 는 로그인 리다이렉트가 날 수 있어 Target Group 이 Unhealthy 로 잡힐 수 있습니다. 앱에 헬스체크 뷰 추가를 요청하거나, 성공 판정 코드에 302를 포함시켜야 합니다 |
| **ASG 확장 시 ALLOWED_HOSTS** | 지금은 고정 사설 IP 목록입니다. ASG 인스턴스 IP는 매번 바뀌고 ALB 헬스체크는 Host 헤더에 대상 IP를 넣으므로, 그 시점에 `{{ ansible_default_ipv4.address }}` 추가 또는 `/health` 뷰 도입이 필요합니다 |
| **Static → S3 + CloudFront** | **불가.** 앱의 `requirements.txt` 에 `django-storages`, `boto3` 가 없습니다. 앱 코드 변경이 선행되어야 하며 Ansible로 해결되지 않습니다. 현재 role 은 로컬 `collectstatic` 만 수행합니다 |

## 주의

- `group_vars/all/vault.yml` 은 절대 커밋하지 마세요 (`.gitignore` 로 차단되어 있음)
- `*.pem` 키 파일도 마찬가지입니다
- `host_key_checking` 을 끄지 마세요. 대신 `ssh-keyscan` / `ssh -J` 로 키를 등록합니다
- AMI는 **Ubuntu 24.04 (Noble)** 전제입니다. Django 6.0이 Python 3.12+ 를 요구합니다
