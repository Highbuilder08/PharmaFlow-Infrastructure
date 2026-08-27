# PharmaFlow Infrastructure Final Documentation

## 1. 문서 목적

이 문서는 PharmaFlow 프로젝트에서 구축한 AWS 인프라의 최종 구조와 설계 목적, Terraform/Ansible 기반 자동화, GitHub Actions CI/CD 검증, 보안 구성 및 실제 검증 결과를 발표와 최종 프로젝트 기록을 위해 정리한 문서이다.

PharmaFlow 인프라는 기존 온프레미스 기반 Django 애플리케이션을 AWS 환경으로 확장하면서 다음 목표를 중심으로 설계하였다.

* Multi-AZ 기반 고가용성 확보
* Web / App / DB 계층 분리
* Auto Scaling 기반 장애 대응
* Terraform 기반 Infrastructure as Code
* Ansible 기반 서버 구성 자동화
* 온프레미스와 AWS 간 하이브리드 연결
* 공유 스토리지 및 관리형 데이터베이스 활용
* CloudWatch / SNS 기반 모니터링
* GitHub Actions 기반 인프라 코드 검증
* GitHub OIDC 기반 AWS 인증
* GitHub Repository 내 운영 Secret 및 환경값 분리

---

# 2. 최종 인프라 개요

최종 서비스 요청 흐름은 다음과 같다.

```text
Internet
   ↓
Route 53
   ↓
Public ALB
   ↓
Nginx ASG
   ↓
Internal ALB
   ↓
Django ASG
   ↓
RDS MariaDB
```

주요 지원 서비스는 다음과 같다.

```text
AWS WAF
   └─ Public ALB Web ACL 연동

ACM
   └─ Public ALB HTTPS 인증서

Amazon EFS
   ├─ Shared Static
   └─ Media / User Upload

CloudWatch
   └─ SNS 관리자 알림

Amazon SES
   └─ 애플리케이션 이메일 전송

WireGuard
   └─ On-Premise ↔ AWS Hybrid Network
```

Infrastructure Automation은 다음 흐름으로 구성하였다.

```text
GitHub Repository
        ↓
GitHub Actions
   ├─ Infrastructure CI
   └─ Infrastructure CD
        ↓ OIDC
AWS IAM Role
        ↓
Terraform / Ansible
```

---

# 3. AWS Region 및 VPC

AWS Region은 서울 리전인 `ap-northeast-2`를 사용한다.

VPC CIDR은 다음과 같다.

```text
10.23.0.0/16
```

인프라는 Public, Web, App, DB Tier로 나누고 각 Tier를 서로 다른 Availability Zone에 배치할 수 있도록 구성하였다.

---

# 4. Multi-AZ Subnet 설계

## Public Tier

```text
Public Subnet A
10.23.1.0/24

Public Subnet C
10.23.2.0/24
```

Public Tier에는 외부와 직접 연결이 필요한 리소스를 배치한다.

주요 리소스:

* Public ALB
* Bastion Host
* NAT Instance
* WireGuard Gateway

## Web Private Tier

```text
Web Private Subnet A
10.23.21.0/24

Web Private Subnet C
10.23.22.0/24
```

Web Tier에는 Nginx Auto Scaling Group 인스턴스를 배치한다.

## App Private Tier

```text
App Private Subnet A
10.23.31.0/24

App Private Subnet C
10.23.32.0/24
```

App Tier에는 Django Auto Scaling Group 인스턴스를 배치한다.

## DB Private Tier

```text
DB Private Subnet A
10.23.41.0/24

DB Private Subnet C
10.23.42.0/24
```

DB Tier에는 Amazon RDS MariaDB Multi-AZ 환경을 구성한다.

### 설계 목적

각 서비스 계층을 네트워크 수준에서 분리하고 주요 서비스가 하나의 Availability Zone 장애에 종속되지 않도록 Multi-AZ 구조를 적용하였다.

---

# 5. Public ALB

외부 사용자 요청의 최초 진입점으로 Public Application Load Balancer를 사용한다.

주요 역할:

* 외부 HTTP / HTTPS 요청 수신
* HTTP 80 요청을 HTTPS 443으로 Redirect
* 정상 상태의 Nginx Target으로 트래픽 분산
* ACM 인증서를 이용한 HTTPS 처리
* AWS WAF Web ACL 연동

전체 요청 흐름:

```text
Internet
   ↓
Route 53
   ↓
Public ALB
   ↓
Nginx ASG
```

Public ALB를 통해 사용자가 개별 Nginx EC2의 IP를 직접 참조하지 않도록 구성하였다.

---

# 6. AWS WAF 및 HTTPS

Public ALB에는 AWS WAF Web ACL을 연결하여 웹 요청에 대한 보안 정책을 적용하였다.

WAF는 독립적인 네트워크 중계 장비가 아니라 Public ALB에 연결된 Web ACL 형태로 동작한다.

ACM Certificate를 Public ALB HTTPS Listener에 적용하여 HTTPS 통신을 구성하였다.

구조:

```text
Route 53
   ↓
Public ALB
   ↑
   ├─ ACM Certificate
   └─ AWS WAF Web ACL
```

실제 HTTPS 요청에서 정상 HTTP 200 응답을 확인하였다.

---

# 7. Nginx Web Tier

Nginx는 Web Tier에서 다음 역할을 담당한다.

* Reverse Proxy
* Static 파일 제공
* App Tier로 동적 요청 전달

Nginx는 단일 EC2가 아니라 Auto Scaling Group으로 구성하였다.

```text
Nginx ASG
Desired Capacity: 2
Multi-AZ
```

Nginx 인스턴스는 서로 다른 Availability Zone에 배치하며 Public ALB Target Group에 등록된다.

이를 통해 단일 Nginx 인스턴스가 전체 Web Tier의 Single Point of Failure가 되는 것을 방지하였다.

---

# 8. Internal ALB

Nginx와 Django 사이에는 Internal Application Load Balancer를 구성하였다.

구조:

```text
Nginx ASG
   ↓
Internal ALB
   ↓
Django ASG
```

Internal ALB 도입의 핵심 목적은 특정 Django EC2의 Private IP 의존성을 제거하는 것이다.

Django ASG의 인스턴스는 장애 복구나 Instance Refresh 과정에서 교체될 수 있으며 Private IP도 변경될 수 있다.

따라서 Nginx가 특정 Django Private IP를 직접 참조하는 대신 Internal ALB DNS를 Backend로 사용하도록 구성하였다.

효과:

* Django Private IP 직접 의존성 제거
* Django 인스턴스 교체 시 Nginx 설정 변경 불필요
* 정상 Django Target으로 자동 분산
* Web Tier와 App Tier 독립적인 확장 가능
* Django 서버의 외부 직접 노출 방지

---

# 9. Django App Tier

Django 애플리케이션 서버는 App Private Subnet의 Auto Scaling Group으로 구성하였다.

```text
Django ASG
Desired Capacity: 2
Multi-AZ
```

Django 인스턴스는 Internal ALB Target Group에 등록되어 Nginx에서 전달된 동적 요청을 처리한다.

최종 운영 구성에서는 Golden AMI 및 Launch Template을 이용해 동일한 구성의 Django EC2를 생성할 수 있도록 구성하였다.

장애시험 과정에서 사용된 이전 AMI 버전과 최종 운영 버전은 구분하여 관리하였다.

---

# 10. Auto Scaling과 Golden AMI

Nginx와 Django 모두 Auto Scaling Group 기반으로 구성하였다.

Auto Scaling을 통해 다음 효과를 확보한다.

* Desired Capacity 유지
* 인스턴스 종료 또는 불능 시 대체 인스턴스 생성
* Multi-AZ 인스턴스 배치
* Launch Template 기반 동일 구성 생성

Golden AMI와 Launch Template의 역할은 서로 다르다.

## Golden AMI

서버에 필요한 소프트웨어와 설정이 준비된 기준 이미지이다.

## Launch Template

EC2 생성 조건을 정의한다.

예:

* 사용할 AMI
* Instance Type
* Security Group
* EC2 생성 옵션

ASG는 Launch Template을 기반으로 필요한 EC2 인스턴스를 생성한다.

---

# 11. EFS 공유 스토리지

Auto Scaling 환경에서는 EC2 인스턴스가 교체될 수 있기 때문에 특정 서버의 로컬 디스크에 Static이나 Media 파일을 저장하는 방식은 적합하지 않다.

이를 해결하기 위해 Amazon EFS를 공유 스토리지로 사용하였다.

## Shared Static

```text
Django
   ↓
collectstatic
   ↓
Amazon EFS
   ↑
Nginx ASG
```

Django의 `collectstatic` 결과를 EFS에 저장하고 Nginx 인스턴스들이 동일한 파일 시스템을 사용하도록 구성하였다.

이를 통해 어느 Nginx 인스턴스가 요청을 처리하더라도 동일한 Static 파일을 제공할 수 있다.

실제 외부 Static 요청에서 HTTP 200 응답을 확인하였다.

## Media

사용자 업로드 파일도 특정 EC2에 종속되지 않도록 공유 스토리지 구조를 적용하였다.

---

# 12. Amazon RDS MariaDB

애플리케이션 데이터베이스는 Amazon RDS MariaDB를 사용한다.

주요 특징:

* DB Private Tier 배치
* Django 계층을 통한 제한된 접근
* Multi-AZ 구성
* Primary / Standby 구조
* 관리형 데이터베이스 서비스 활용

실제 RDS Failover 시험을 수행하고 AWS Event에서 Failover 시작 및 완료 기록을 확인하였다.

따라서 RDS Multi-AZ는 설정 여부뿐 아니라 실제 Failover 동작까지 검증하였다.

---

# 13. Bastion Host

Private Subnet의 EC2에 관리자가 인터넷에서 직접 SSH로 접근하지 않도록 Bastion Host 기반 관리 구조를 사용한다.

```text
Admin / Developer
       ↓
     SSH 22
       ↓
Bastion Host
       ↓
Private EC2
```

관리자 접근 범위는 Terraform의 `admin_cidr` 변수로 관리한다.

효과:

* Private EC2의 직접 인터넷 노출 방지
* 관리 접근 경로 제한
* 관리자 CIDR 기반 접근 제어

---

# 14. NAT Instance

Private Tier 인스턴스가 패키지 설치 및 외부 서비스 접근 등을 위해 Outbound Internet 통신을 수행할 수 있도록 NAT Instance를 구성하였다.

```text
Private Tier
    ↓
NAT Instance
    ↓
Internet Gateway
    ↓
Internet
```

교육 및 프로젝트 환경에서 비용을 고려하여 NAT Gateway 대신 NAT Instance를 적용하였다.

향후 실제 운영 규모와 가용성 요구가 증가할 경우 Managed NAT Gateway 도입을 고려할 수 있다.

---

# 15. WireGuard 하이브리드 네트워크

기존 온프레미스 환경을 AWS와 연계하기 위해 WireGuard 기반 Site-to-Site VPN 구조를 구성하였다.

```text
On-Premise Server1
192.168.32.87/24
       ↕
WireGuard Site-to-Site VPN
       ↕
AWS WireGuard Gateway EC2
UDP 51820
       ↕
AWS VPC
```

검증 항목:

* WireGuard Peer 연결
* Handshake 확인
* AWS와 On-Premise 간 Ping
* HTTP 통신
* Stop / Start 이후 재연결

이를 통해 온프레미스 환경을 완전히 제거하지 않고 AWS와 연계한 Hybrid Infrastructure를 구성하였다.

---

# 16. Security Group 계층 분리

각 Tier마다 별도의 Security Group을 사용하여 필요한 서비스 간 통신만 허용하도록 구성하였다.

대표적인 요청 경로는 다음과 같다.

```text
Internet
   ↓
Public ALB : 80 / 443
   ↓
Nginx : 80
   ↓
Internal ALB : 80
   ↓
Django : 8000
   ↓
RDS : 3306
```

관리 SSH는 Bastion을 경유하도록 제한하였다.

Security Group은 가능한 경우 특정 IP를 직접 허용하는 것보다 이전 Tier의 Security Group을 기준으로 접근을 제한하는 방식으로 구성하였다.

---

# 17. Route 53

서비스 도메인 관리를 위해 Amazon Route 53을 사용하였다.

Route 53에서 서비스 도메인을 Public ALB로 연결하여 사용자가 개별 EC2 주소가 아닌 서비스 도메인으로 접근할 수 있도록 구성하였다.

---

# 18. Amazon SES

애플리케이션 이메일 발송을 위해 Amazon SES를 구성하였다.

구현 및 검증 항목:

* SES Domain Identity
* Easy DKIM
* SPF
* DMARC
* Custom MAIL FROM
* SMTP 연결
* Django `send_mail`
* 실제 외부 이메일 수신 확인

SES SMTP 통신 과정에서 NAT Security Group의 Outbound 정책으로 인해 SMTP 587 연결 문제가 발생한 사례가 있었다.

해당 문제는 네트워크 접근 정책을 점검하고 수정하여 해결하였다.

이 과정은 인프라 Troubleshooting 사례로 기록하였다.

---

# 19. CloudWatch 및 SNS 모니터링

AWS 인프라 상태 모니터링에는 Amazon CloudWatch를 사용하고 알림 전달에는 Amazon SNS를 사용하였다.

주요 대상:

* Public ALB
* Nginx Target Group
* Django Target Group
* EC2 / ASG
* RDS

흐름:

```text
AWS Resource / Metric
        ↓
CloudWatch Alarm
        ↓
Amazon SNS
        ↓
Administrator Email
```

SNS의 ALARM / OK 이메일 알림 동작을 실제로 확인하였다.

## CloudWatch Alarm 해석 주의사항

CloudWatch Alarm은 장애가 발생하는 즉시 무조건 ALARM으로 전환되는 것이 아니다.

다음 설정에 따라 상태가 결정된다.

* Metric
* Period
* Evaluation Period
* Threshold
* Missing Data 처리 방식

일부 시험에서는 Missing Datapoint를 Breaching으로 처리한 Alarm이 존재하였다.

따라서 CloudWatch 이메일 한 장만으로 실제 HealthyHostCount 감소를 단정하지 않고 다음 증빙을 함께 사용하여 장애 상황을 검증하였다.

* ASG Activity
* Target Health
* EC2 상태
* 실제 HTTP 응답
* 대체 인스턴스 생성 결과

---

# 20. 실제 장애복구 검증

고가용성은 설정만 확인하는 것이 아니라 실제 장애시험을 통해 검증하였다.

## Nginx

검증 흐름:

```text
Nginx 인스턴스 1대 종료
        ↓
Public ALB가 정상 Target으로 트래픽 전달
        ↓
ASG Desired Capacity 부족
        ↓
신규 Nginx EC2 생성
        ↓
Target Group 등록
        ↓
Health Check 통과
        ↓
2 of 2 Healthy 복구
```

장애 시간대에도 Public ALB의 HTTP 2XX 응답 기록을 확인하였다.

## Django

Django ASG에서도 인스턴스 교체 및 Target Health를 통해 App Tier의 복구 동작을 검증하였다.

## RDS

Multi-AZ Failover를 수행하고 실제 AWS RDS Event의 Failover 시작 및 완료 기록을 확인하였다.

---

# 21. Instance Refresh와 장애복구의 차이

Instance Refresh와 장애 자동복구는 목적이 다르다.

## Instance Refresh

새로운 Launch Template 또는 Golden AMI 버전을 기존 ASG 인스턴스에 순차적으로 적용하는 배포 및 갱신 과정이다.

## Unhealthy / Instance Replacement

인스턴스 종료 또는 비정상 상태로 인해 ASG의 Desired Capacity가 부족해졌을 때 새로운 인스턴스를 생성하여 수량을 회복하는 장애 대응 과정이다.

두 동작을 동일한 장애복구 증빙으로 해석하지 않고 별도로 검증하였다.

---

# 22. Terraform Infrastructure as Code

AWS 인프라는 Terraform으로 코드화하였다.

Terraform이 담당하는 주요 영역:

* VPC
* Subnet
* Route
* Security Group
* ALB
* Target Group
* Auto Scaling
* Launch Template
* RDS
* EFS
* IAM
* 기타 AWS Infrastructure Resource

Terraform을 통해 다음 효과를 얻었다.

* 인프라 재현 가능
* Git 기반 변경 이력 관리
* 수동 설정 오류 감소
* 실제 환경과 코드 상태 비교
* 팀 협업 가능

---

# 23. Ansible Configuration Management

Terraform과 Ansible의 역할은 분리하였다.

## Terraform

Infrastructure Resource를 생성하고 관리한다.

## Ansible

생성된 서버 내부의 설정을 관리한다.

대표적인 Ansible 영역:

* Nginx 구성
* Django 서버 구성
* 패키지 설치
* 서비스 설정
* 애플리케이션 실행 환경 구성

구조:

```text
Terraform
   ↓
AWS Infrastructure 생성
   ↓
Ansible
   ↓
Server Configuration
```

---

# 24. Git Branch 및 Pull Request 협업

Infrastructure Repository에서는 기능별 Branch를 사용하여 팀원이 독립적으로 작업하도록 구성하였다.

기본 흐름:

```text
main
  ↓
feature / fix branch
  ↓
작업 및 Commit
  ↓
Push
  ↓
Pull Request
  ↓
검토 및 CI
  ↓
main Merge
```

Django, Nginx, Terraform 및 문서 작업을 개별 브랜치에서 진행한 후 PR 기반으로 통합하였다.

이를 통해 동시에 작업하면서도 `main`을 안정적으로 유지하였다.

---

# 25. Repository Secret 및 환경값 관리

프로젝트 진행 과정에서 실제 환경값이 공용 Git Repository에 포함되지 않도록 보안 구성을 개선하였다.

적용 내용:

* 실제 Private IP를 공용 Ansible 변수에서 제거
* `local.yml`을 Git 추적 대상에서 제외
* `vault.yml` 등 Secret 파일 추적 여부 검사
* Example 파일과 실제 운영 설정 분리
* DB Password를 GitHub Secret으로 관리
* GitHub Actions AWS 장기 Access Key 미사용
* GitHub Environment를 이용한 Production 설정 분리

---

# 26. Infrastructure CI

`.github/workflows/infra-ci.yml`을 통해 Infrastructure CI를 구성하였다.

실행 조건:

```text
Pull Request → main

Push → main
```

## Terraform Check

수행 항목:

```text
terraform fmt -check -recursive
terraform init -backend=false -input=false
terraform validate
```

## Ansible Check

수행 항목:

```text
Ansible 설치
Collection 설치
Django Playbook syntax-check
Nginx Playbook syntax-check
```

## Repository Security Check

실제 Secret 파일이 Git에 Tracking되고 있는지 검사한다.

검사 대상 예:

```text
ansible/group_vars/all/vault.yml
ansible/group_vars/all/local.yml
```

이를 통해 잘못된 코드나 Secret 파일이 Repository에 반영되는 위험을 줄였다.

---

# 27. GitHub Environment - production

Infrastructure CD에서는 GitHub의 `production` Environment를 사용한다.

운영 설정은 일반 Variables와 Secrets로 분리하였다.

## Variables

```text
ADMIN_CIDR
AWS_REGION
AWS_ROLE_ARN
DB_NAME
DB_USERNAME
DOMAIN_NAME
EC2_KEY_NAME
```

## Secrets

```text
DB_PASSWORD
ALERT_EMAIL
```

GitHub Actions에서는 이 값들을 Terraform이 인식할 수 있도록 `TF_VAR_*` 환경변수로 전달한다.

예:

```text
ADMIN_CIDR
   ↓
TF_VAR_admin_cidr

EC2_KEY_NAME
   ↓
TF_VAR_ec2_key_name

DB_PASSWORD
   ↓
TF_VAR_db_password
```

---

# 28. GitHub OIDC 기반 AWS 인증

GitHub Actions에서 장기간 사용하는 AWS Access Key와 Secret Access Key를 저장하지 않기 위해 OIDC 인증 방식을 적용하였다.

인증 흐름:

```text
GitHub Actions
      ↓
OIDC Token
      ↓
AWS STS
AssumeRoleWithWebIdentity
      ↓
AWS IAM Role
      ↓
Temporary Credentials
      ↓
Terraform
```

GitHub Actions Workflow에는 다음 권한을 부여한다.

```yaml
permissions:
  contents: read
  id-token: write
```

AWS IAM Role의 Trust Policy를 통해 허용된 GitHub Repository 및 Production Environment가 Role을 사용할 수 있도록 제한하였다.

AWS CloudTrail에서도 `AssumeRoleWithWebIdentity` 관련 기록을 확인하여 실제 OIDC 인증이 수행되는 것을 검증하였다.

### 보안상 장점

* 장기 AWS Access Key 저장 불필요
* Workflow 실행 시 임시 Credentials 사용
* Repository / Environment 기준 Role 사용 범위 제한
* AWS 측에서 인증 기록 추적 가능

---

# 29. Infrastructure CD

`.github/workflows/infra-cd.yml`을 통해 Production Infrastructure 검증 Workflow를 구성하였다.

실행 방식:

```text
workflow_dispatch
```

즉 사용자가 GitHub Actions에서 수동으로 실행하는 구조이다.

실행 흐름:

```text
GitHub Environment: production
        ↓
Variables / Secrets
        ↓
TF_VAR_*
        ↓
GitHub OIDC Claim 확인
        ↓
AWS OIDC 인증
        ↓
aws sts get-caller-identity
        ↓
terraform init
        ↓
terraform validate
        ↓
terraform plan
```

---

# 30. 현재 CD의 범위

현재 Infrastructure CD는 자동 `terraform apply`를 수행하지 않는다.

현재 구현 범위:

```text
OIDC Authentication
        ↓
Terraform Init
        ↓
Terraform Validate
        ↓
Terraform Plan
        ↓
STOP
```

`terraform apply`는 자동으로 실행되지 않는다.

이는 운영 인프라가 승인 없이 자동 변경되는 것을 방지하기 위한 현재 프로젝트 범위의 안전한 구성이다.

따라서 발표에서는 다음과 같이 설명한다.

> 현재 Infrastructure CD는 Production Environment에 OIDC로 인증한 후 Terraform Plan까지 자동 검증하며, Apply는 의도적으로 자동화하지 않았습니다.

---

# 31. Infrastructure CD 문제 해결 과정

Infrastructure CD 최초 시험에서 Terraform이 다음 필수 변수들을 전달받지 못하는 문제가 발생하였다.

예:

```text
db_password is not set
domain_name is not set
alert_email is not set
```

원인은 GitHub Actions Workflow에 작성한 `TF_VAR_*` 환경변수 전달 설정이 로컬 작업 디렉터리에만 존재하고 아직 `main`에 반영되지 않았기 때문이었다.

해결 과정:

```text
GitHub Environment 값 확인
        ↓
Terraform 변수명 확인
        ↓
infra-cd.yml TF_VAR_* 매핑 확인
        ↓
로컬 Git Diff 확인
        ↓
변경사항이 아직 GitHub main에 없음을 확인
        ↓
별도 Fix Branch 생성
        ↓
Commit / Push / Pull Request
        ↓
main Merge
        ↓
Infrastructure CD 재실행
        ↓
SUCCESS
```

이 과정을 통해 GitHub Environment, Workflow, Terraform Variable 간 연결 관계를 검증하였다.

---

# 32. Terraform 최종 검증

Infrastructure CD를 최종 실행한 결과 전체 Workflow가 성공하였다.

최종 Terraform Plan 결과:

```text
No changes. Your infrastructure matches the configuration.
```

이 결과는 실행 시점 기준 Terraform 코드와 Terraform State 및 실제 관리 대상 AWS Infrastructure 사이에 추가 변경 계획이 없음을 의미한다.

즉 최종 검증 시 다음 상태를 확인하였다.

* GitHub Environment 정상 참조
* GitHub Variables 정상 전달
* GitHub Secrets 정상 전달
* `TF_VAR_*` 정상 인식
* OIDC Token 발급 정상
* AWS IAM Role Assume 정상
* AWS STS Caller Identity 정상
* Terraform Backend 초기화 정상
* Terraform Validate 성공
* Terraform Plan 성공
* 추가 변경 계획 없음

---

# 33. 주요 Troubleshooting

## 1. Terraform 변수 미전달

### 문제

GitHub Actions에서 Terraform Required Variable 오류 발생.

### 원인

`TF_VAR_*` 설정이 로컬 Workflow 파일에만 존재하고 GitHub `main`에 반영되지 않음.

### 해결

별도 Fix Branch에서 Commit / Push / PR / Merge 후 Infrastructure CD 재실행.

---

## 2. OIDC Trust Policy

GitHub Actions의 OIDC Claim과 AWS IAM Role Trust Policy 조건이 정확하게 일치해야 한다.

Repository 및 Environment Claim을 확인하고 IAM Trust Policy를 수정하여 AWS Role 인증을 정상화하였다.

---

## 3. SES SMTP 587 연결

SES SMTP 연결 시험 중 NAT 관련 Network / Security Group Outbound 정책을 확인하고 필요한 통신 정책을 수정하여 SMTP 통신을 정상화하였다.

---

## 4. Auto Scaling 환경의 Static 공유

Django와 Nginx가 서로 다른 ASG 인스턴스로 분리되면서 로컬 Static 파일을 직접 공유할 수 없었다.

EFS Shared Static 구조를 적용하여 해결하였다.

---

## 5. Django Private IP 의존성

Nginx Backend가 특정 Django EC2 Private IP를 직접 사용하면 Django 인스턴스 교체 시 설정 변경이 필요하다.

Internal ALB를 도입하여 Nginx가 개별 Django IP가 아닌 Internal ALB DNS를 사용하도록 변경하였다.

---

# 34. 최종 검증 항목

프로젝트 최종 단계에서 다음 항목들을 검증하였다.

## Network / Load Balancing

* Route 53 → Public ALB
* HTTPS 정상 응답
* Public ALB Target Health
* Internal ALB → Django Target
* Multi-AZ 배치

## Nginx

* ASG Desired Capacity
* Multi-AZ
* Golden AMI / Launch Template
* Target Group Health
* 실제 인스턴스 종료 및 자동 대체
* Static HTTP 200

## Django

* ASG Multi-AZ
* Target Group Health
* Golden AMI / Launch Template
* Instance 교체 / Refresh

## RDS

* MariaDB
* Multi-AZ
* Snapshot
* 실제 Failover Event

## EFS

* Multi-AZ Mount Target
* NFS Mount
* Shared Static
* 외부 Static HTTP 200

## Monitoring

* CloudWatch Alarm
* SNS Notification
* 실제 Email 수신

## Hybrid Network

* WireGuard Handshake
* Ping
* HTTP 통신
* Stop / Start 후 연결

## SES

* DKIM
* SPF
* DMARC
* Custom MAIL FROM
* SMTP
* Django Email
* 외부 Email 수신

## Infrastructure Automation

* Terraform Format
* Terraform Validate
* Ansible Syntax Check
* Repository Security Check
* GitHub Environment
* TF_VAR 전달
* GitHub OIDC
* AWS IAM Role
* Terraform Plan
* 최종 No Changes

---

# 35. 현재 구현 범위와 향후 개선

현재 프로젝트에서 검증한 자동화는 Production Infrastructure의 Terraform Plan까지이다.

향후 실제 운영 환경에서는 다음 항목을 추가로 고려할 수 있다.

* 승인 기반 `terraform apply`
* GitHub Environment Required Reviewer
* NAT Instance → NAT Gateway
* WAF Rule 세분화
* CloudWatch Alarm Threshold 튜닝
* Auto Scaling Policy 고도화
* Centralized Logging
* AWS Backup 정책 강화
* Terraform Module 구조 고도화
* 별도의 Development / Staging / Production Environment 분리

현재 구현하지 않은 기능은 최종 구현 완료 사항과 구분하여 향후 개선 항목으로 관리한다.

---

# 36. 발표 핵심 요약

PharmaFlow 프로젝트에서는 단순히 Django 애플리케이션을 AWS EC2에서 실행하는 것에 그치지 않고 운영 환경을 고려한 인프라 구조로 확장하였다.

핵심 구현은 다음과 같다.

```text
Multi-AZ
+
Public / Web / App / DB Tier 분리
+
Public ALB / Internal ALB
+
Nginx / Django Auto Scaling
+
RDS Multi-AZ
+
EFS Shared Storage
+
WireGuard Hybrid Network
+
CloudWatch / SNS
+
Route 53 / ACM / WAF / SES
+
Terraform IaC
+
Ansible Configuration Management
+
Git Branch / Pull Request
+
GitHub Actions CI
+
GitHub Environment
+
OIDC / AWS IAM Role
+
Production Terraform Plan
```

최종 Infrastructure CD에서 다음 결과를 확인하였다.

```text
No changes.
Your infrastructure matches the configuration.
```

이를 통해 코드 기반 Infrastructure 관리와 실제 AWS 환경 간 일치 상태를 최종 검증하였다.

---

# 37. 발표 예상 질문

## Q1. Terraform과 Ansible을 왜 같이 사용했는가?

Terraform은 VPC, Subnet, ALB, RDS, EFS, ASG 등의 AWS Infrastructure Resource를 생성하는 역할을 담당하고 Ansible은 생성된 EC2 내부의 Nginx와 Django 설정을 담당한다.

두 도구의 역할을 분리함으로써 Infrastructure Provisioning과 Server Configuration을 각각 코드로 관리할 수 있다.

### 발표 답변

> Terraform은 AWS 인프라 자체를 만들고, Ansible은 생성된 서버 내부의 Nginx와 Django 환경을 설정하는 역할로 분리했습니다.

---

## Q2. 왜 Multi-AZ로 구성했는가?

하나의 Availability Zone에 모든 서버를 배치하면 해당 AZ 장애가 전체 서비스 장애로 이어질 수 있다.

따라서 Nginx, Django 및 RDS를 여러 AZ에 분산하여 단일 AZ 의존성을 줄였다.

### 발표 답변

> 하나의 가용 영역 장애가 전체 서비스 장애로 이어지는 것을 줄이기 위해 주요 계층을 Multi-AZ로 구성했습니다.

---

## Q3. 왜 Public ALB와 Internal ALB를 모두 사용했는가?

Public ALB는 외부 요청을 Nginx ASG로 분산하고 Internal ALB는 Nginx 요청을 Django ASG로 분산한다.

Internal ALB를 통해 Nginx가 특정 Django Private IP를 직접 참조하지 않아도 된다.

### 발표 답변

> Public ALB는 외부 진입점이고 Internal ALB는 Django 계층의 내부 진입점입니다. 이를 통해 Web과 App Tier를 분리하고 Django의 특정 Private IP 의존성을 제거했습니다.

---

## Q4. 왜 NAT Gateway 대신 NAT Instance를 사용했는가?

프로젝트 및 교육 환경에서 비용을 고려하여 NAT Instance를 사용하였다.

다만 Managed Service의 가용성과 운영 편의성이 중요한 실제 Production 환경에서는 NAT Gateway를 고려할 수 있다.

### 발표 답변

> 프로젝트 규모와 비용을 고려해 NAT Instance를 선택했습니다. 실제 운영 환경에서 관리성과 가용성을 우선한다면 NAT Gateway 전환을 고려할 수 있습니다.

---

## Q5. 왜 WireGuard를 사용했는가?

기존 온프레미스 환경을 완전히 제거하지 않고 AWS와 Private Network로 연계하기 위해 사용하였다.

### 발표 답변

> 기존 온프레미스 자원을 유지하면서 AWS로 확장하기 위해 WireGuard Site-to-Site VPN을 구성해 하이브리드 환경을 구현했습니다.

---

## Q6. 왜 GitHub Actions에 AWS Access Key를 저장하지 않았는가?

장기 Access Key가 GitHub Secret에 저장되면 Key Lifecycle 관리와 노출 위험이 발생한다.

OIDC를 사용하면 Workflow 실행 시점에 AWS IAM Role의 임시 Credentials를 발급받을 수 있다.

### 발표 답변

> 장기 AWS Access Key를 저장하지 않기 위해 GitHub OIDC와 AWS IAM Role을 사용했습니다. Workflow 실행 시점에만 임시 자격 증명을 발급받도록 구성했습니다.

---

## Q7. 현재 CD에서 Terraform Apply도 자동으로 실행되는가?

아니다.

현재 CD의 목적은 Production 환경에서 OIDC 인증과 Terraform Plan까지 자동 검증하는 것이다.

`terraform apply`는 자동화하지 않았다.

### 발표 답변

> 현재 CD는 Production 환경에 OIDC로 인증하고 Terraform Plan까지 검증합니다. 운영 인프라가 승인 없이 변경되지 않도록 Apply는 의도적으로 자동화하지 않았습니다.

---

## Q8. `No changes` 결과는 무엇을 의미하는가?

Terraform이 현재 관리하는 State와 실제 Infrastructure를 기준으로 코드와 비교했을 때 추가 생성, 수정 또는 삭제 계획이 없다는 의미이다.

### 발표 답변

> Terraform 코드와 현재 관리 중인 AWS 인프라를 비교했을 때 변경할 리소스가 없다는 의미이며, 최종 검증 시 코드와 인프라가 일치하는 상태를 확인했습니다.

---

## Q9. CloudWatch Alarm이 장애 때 항상 울리는가?

반드시 그렇지는 않다.

CloudWatch Alarm은 Metric, Period, Evaluation Period, Threshold 및 Missing Data 처리 방식에 따라 상태를 판단한다.

장애가 평가기간보다 빠르게 복구되면 ALARM 상태로 전환되기 전에 정상화될 수도 있다.

### 발표 답변

> CloudWatch Alarm은 장애 발생 자체가 아니라 설정된 평가조건을 기준으로 상태가 변경됩니다. 그래서 장애 지속시간이 짧으면 ALARM 전환 전에 정상화될 수 있으며, 실제 장애복구는 ASG Activity와 Target Health 등의 증빙도 함께 확인했습니다.

---

## Q10. 가장 중요한 인프라 개선점은 무엇인가?

단일 서버와 특정 Private IP에 의존하던 구조를 Multi-AZ, Load Balancer, Auto Scaling 및 Shared Storage 기반 구조로 변경하고 모든 Infrastructure를 Terraform과 Ansible을 이용해 코드로 관리하도록 개선한 점이다.

또한 GitHub Actions와 OIDC를 결합해 Infrastructure 변경 전 자동 검증과 AWS 인증 과정의 보안성을 강화하였다.

### 발표 답변

> 가장 큰 변화는 단일 서버 중심 구조를 Multi-AZ와 Auto Scaling 기반 구조로 개선하고, 이를 Terraform·Ansible·GitHub Actions로 코드화하고 자동 검증할 수 있게 만든 것입니다.
