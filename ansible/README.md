# PharmaFlow Ansible

Terraform이 만든 EC2 **안을 채우는** 단계입니다.
(Terraform = 서버 생성 / Ansible = 서버 구성. 서로 자동 연동되지 않고 사람이 IP를 넘겨줍니다.)

## 구조

```
ansible/
├── ansible.cfg                 기본 설정
├── inventory/prod.ini          대상 서버 목록  ← EC2 생성 후 IP 교체 필요
├── group_vars/
│   ├── all.yml                 공통 변수 (비밀값 아님)
│   └── vault.yml.example       비밀값 템플릿
├── site.yml                    배포 지휘서
└── roles/
    ├── django/                 팀원2 담당
    └── nginx/                  팀원3 담당 (예정)
```

## 최초 1회 준비

```bash
cd ansible

# 1) 비밀값 파일 생성
cp group_vars/vault.yml.example group_vars/vault.yml
vi group_vars/vault.yml                    # DB 비밀번호, HIRA 키 입력
ansible-vault encrypt group_vars/vault.yml # 암호화

# 2) EC2 접속 키 배치
cp <다운로드한키>.pem ~/.ssh/pharmaflow.pem
chmod 600 ~/.ssh/pharmaflow.pem
```

## 팀장 EC2 생성 후

```bash
# 1) 실제 IP 확인
cd ../environments/prod && terraform output

# 2) IP 교체 (2곳)
#    - inventory/prod.ini  의 ansible_host
#    - group_vars/all.yml  의 *_private_ip

# 3) 호스트 키 등록 (첫 접속 질문 방지)
ssh-keyscan -H 10.0.1.10 >> ~/.ssh/known_hosts

# 4) 접속 확인
ansible django -m ping

# 5) 예행연습 - 실제로 바꾸지 않고 뭐가 바뀔지만 확인
ansible-playbook site.yml --limit django --ask-vault-pass --check --diff

# 6) 실제 적용
ansible-playbook site.yml --limit django --ask-vault-pass
```

## EC2 없이 지금 할 수 있는 검증

```bash
ansible-playbook site.yml --syntax-check   # 문법 검사 (접속 안 함)
ansible-inventory --graph                  # 인벤토리 확인
```

## django role 이 하는 일

| 순서 | 내용 |
|---|---|
| 1 | 빌드/런타임 apt 패키지 설치 |
| 2 | 앱 디렉터리 생성 |
| 3 | PharmaFlow 소스 clone |
| 4 | venv 생성 + requirements.txt 설치 |
| 5 | SECRET_KEY 생성 (최초 1회만) |
| 6 | `.env` 배포 |
| 7 | `pharmaflow.service` systemd 유닛 배포 |
| 8 | NFS media 마운트 (선택) |
| 9 | migrate + collectstatic |
| 10 | logrotate 설정 배치 |
| 11 | 서비스 활성화·시작 |

근거: 앱 저장소의 `deploy/manual/운영매뉴얼.md`, `deploy/SECURITY_AND_SETUP.md`

## 팀원3과 맞춰야 할 것

Django EC2와 Nginx EC2가 분리되어 있으므로:

- 이 role 은 Gunicorn 을 `0.0.0.0:8000` 에 바인딩합니다
  (앱 저장소 `gunicorn.conf.py` 기본값 `127.0.0.1:8000` 으로는 다른 EC2에서 접근 불가)
- 팀원3의 Nginx `proxy_pass` 는 `http://<Django EC2 사설 IP>:8000` 이 되어야 합니다
- 팀장님 보안그룹에서 Nginx EC2 → Django EC2 8000 포트 인바운드 허용이 필요합니다

## 팀 확인이 필요한 미확정 사항

| 항목 | 상태 |
|---|---|
| **Static → S3 + CloudFront** | **불가.** 앱의 `requirements.txt` 에 `django-storages`, `boto3` 가 없습니다. 앱 코드 변경이 선행되어야 하며 Ansible로 해결되지 않습니다. 현재 role 은 로컬 `collectstatic` 만 수행합니다 |
| **ALB Health Check 경로** | 앱에 전용 헬스체크 URL이 없습니다(`/health` 등). `/` 는 로그인 리다이렉트가 날 수 있어 Target Group 이 Unhealthy 로 잡힐 수 있습니다. 앱에 헬스체크 뷰 추가를 요청하거나, 성공 판정 코드에 302를 포함시켜야 합니다 |
| **Private Subnet 접속 경로** | Django EC2에 Public IP가 없으면 Ansible이 직접 붙지 못합니다. Bastion 경유(`ProxyJump`) 또는 SSM 중 무엇을 쓸지 팀 결정이 필요합니다 |
| **RDS 엔드포인트 / EFS DNS** | `defaults/main.yml` 에 `REPLACE-WITH-...` 로 두었습니다. terraform output 나오면 교체 |

## 주의

- `group_vars/vault.yml` 은 절대 커밋하지 마세요 (`.gitignore` 로 차단되어 있음)
- `*.pem` 키 파일도 마찬가지입니다
- `host_key_checking` 을 끄지 마세요. 대신 `ssh-keyscan` 으로 키를 등록합니다
