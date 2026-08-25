# PharmaFlow 전용 이메일 인프라 구성 조사

## 1. 목적

`pharmaflow.homes` 도메인을 이용하여 다음과 같은 프로젝트 전용 이메일 주소를
실제로 사용할 수 있도록 필요한 이메일 인프라를 조사한다.

- `noreply@pharmaflow.homes`
  - Django 애플리케이션 발신 전용
- `alerts@pharmaflow.homes`
  - CloudWatch / SNS 운영 알림 수신
- `admin@pharmaflow.homes`
  - 관리자용 일반 메일 수신 및 필요 시 회신

본 문서는 이메일 인프라 구축을 위한 설계 조사 문서이며,
현재 단계에서는 Route53 변경, AWS 리소스 생성, Terraform Apply,
Nginx 설정 변경을 수행하지 않는다.

---

## 2. 도메인만으로 이메일 주소가 생성되지 않는 이유

현재 `pharmaflow.homes`는 Route53 Hosted Zone을 사용하고 있으며
웹 서비스는 Route53 Alias Record를 통해 Public ALB로 연결되어 있다.

하지만 도메인을 보유하고 있다는 것만으로

- `admin@pharmaflow.homes`
- `alerts@pharmaflow.homes`
- `noreply@pharmaflow.homes`

등의 이메일 주소가 자동으로 생성되지는 않는다.

이메일을 실제로 사용하려면 별도의 메일 발신 및 수신 시스템이 필요하다.

특히 이메일 수신을 위해서는 DNS의 MX(Mail Exchanger) Record를 통해
`@pharmaflow.homes` 메일을 어떤 Mail Service가 처리할 것인지 지정해야 한다.

---

## 3. 현재 PharmaFlow 알림 구조

현재 Terraform에는 CloudWatch Alarm과 SNS Topic 및 Email Subscription이
이미 구성되어 있다.

현재 구조:

```text
CloudWatch Alarm
       ↓
SNS Topic
(pharmaflow-cloudwatch-alerts)
       ↓
Email Subscription
       ↓
var.alert_email
```

CloudWatch Alarm은 다음 항목 등을 감시한다.

- Nginx Target Group Healthy Host Count
- Django Target Group Healthy Host Count
- RDS CPU Utilization
- Public ALB Target 5XX

따라서 향후 `alerts@pharmaflow.homes`를 실제 수신 가능한 메일 주소로 구성하면
기존 SNS Email Subscription의 `alert_email` 환경값으로 사용할 수 있다.

SNS 이메일 구독은 해당 주소에서 Subscription Confirmation을 완료해야
실제 알림 수신이 가능하다.

---

## 4. 권장 이메일 구성

PharmaFlow에서는 애플리케이션 발신과 일반 메일 수신을 분리한다.

```text
                    pharmaflow.homes
                           │
             ┌─────────────┴─────────────┐
             │                           │
      Application Mail              Mailbox
             │                           │
          Django                     Route53 MX
             │                           │
        Amazon SES               Managed Mail Service
             │                    ├─ admin@
  noreply@pharmaflow.homes         └─ alerts@
                                         ↑
                                        SNS
                                         ↑
                                    CloudWatch
```

---

## 5. Django 발신 구성

Django에서 사용자에게 보내는 시스템 메일은 Amazon SES를 사용하는 방식을 권장한다.

```text
Django
  ↓
SMTP
  ↓
Amazon SES
  ↓
noreply@pharmaflow.homes
  ↓
사용자
```

예상 용도:

- 회원 관련 시스템 메일
- 비밀번호 재설정
- 서비스 알림
- 기타 자동 발신

`noreply@pharmaflow.homes`는 자동 발신 전용 주소로 사용하며
일반 사용자가 회신해야 하는 관리용 메일함과 분리한다.

실제 구축 시 SES Domain Identity 인증과 SMTP Credential 등의 설정이 필요하다.

Django의 SMTP 비밀번호 등 민감정보는 Public Git 저장소에 저장하지 않는다.

---

## 6. CloudWatch 운영 알림

운영 알림 주소는 다음과 같이 구성한다.

```text
CloudWatch
   ↓
SNS
   ↓
alerts@pharmaflow.homes
   ↓
운영 담당자
```

현재 Terraform의 다음 구조를 그대로 활용할 수 있다.

```text
aws_cloudwatch_metric_alarm
        ↓
aws_sns_topic.cloudwatch_alerts
        ↓
aws_sns_topic_subscription.cloudwatch_email
        ↓
var.alert_email
```

향후 실제 메일 인프라 구축 후 `var.alert_email`에
`alerts@pharmaflow.homes`를 사용하도록 구성할 수 있다.

SNS Email Subscription 생성 후 해당 메일함에서
AWS의 구독 확인 메일을 승인해야 한다.

---

## 7. 일반 관리자 메일

`admin@pharmaflow.homes`는 사람이 직접 확인하고 필요하면 회신할 수 있는
일반 Mailbox로 운영한다.

예:

```text
Internet Mail
     ↓
Route53 MX
     ↓
Managed Mail Service
     ↓
admin@pharmaflow.homes
```

`alerts@pharmaflow.homes` 역시 같은 Mail Service에서 Mailbox 또는
Alias/Forwarding 주소로 구성할 수 있다.

---

## 8. Amazon SES를 일반 Mailbox로 사용하지 않는 이유

Amazon SES는 애플리케이션 이메일 발송에 적합하다.

SES에는 이메일 수신 기능도 있지만 일반적인 IMAP/POP3 Mailbox 서비스와
동일한 구조가 아니다.

SES를 직접 수신 시스템으로 사용할 경우 다음과 같은 추가 구성이 필요하다.

```text
Internet Mail
      ↓
Route53 MX
      ↓
Amazon SES Receiving
      ↓
Receipt Rule
      ↓
S3 / SNS / 기타 처리 시스템
```

따라서 사람이 로그인하여 메일을 읽고 답장하는 일반 Mailbox가 필요한 경우
관리형 Mail Service를 사용하는 편이 운영이 단순하다.

---

## 9. Amazon WorkMail

Amazon WorkMail은 이번 신규 구축 후보에서 제외한다.

AWS는 Amazon WorkMail 신규 고객 등록을 2026년 4월 30일부터 중단했으며,
서비스 지원도 2027년 3월 31일 종료 예정이다.

따라서 신규 PharmaFlow 이메일 인프라에는 다른 관리형 Mail Service를
사용하는 것이 적절하다.

---

## 10. 필요한 DNS Record

실제 구축 시 Route53에는 선택한 Mail Service와 SES 구성에 따라
메일 관련 DNS Record가 추가로 필요하다.

### MX

Mail Exchanger Record.

`@pharmaflow.homes`로 들어오는 이메일을 어느 Mail Service가 받을지 결정한다.

실제 MX 값은 선택한 Mail Service가 제공하는 값을 사용한다.

### SPF

Sender Policy Framework.

어떤 Mail Server가 해당 도메인을 대신하여 이메일을 발송할 수 있는지
DNS TXT Record를 통해 지정한다.

### DKIM

DomainKeys Identified Mail.

발신 이메일에 전자서명을 적용하여 메일이 정상적인 발신 시스템에서
전송되었는지 검증할 수 있도록 한다.

SES를 사용할 경우 SES Domain Identity 설정 과정에서 필요한
DKIM DNS Record가 제공된다.

### DMARC

Domain-based Message Authentication, Reporting and Conformance.

SPF/DKIM 인증 결과를 이용하여 도메인 위조 및 피싱 메일에 대한
처리 정책을 정의한다.

초기 구축 시 모니터링 정책으로 시작한 후 정상 발신 흐름을 확인하고
점진적으로 강화하는 방법을 고려할 수 있다.

---

## 11. SES Custom MAIL FROM 사용 시

SES의 기본 MAIL FROM을 그대로 사용할 수도 있지만,
향후 도메인 정렬 및 메일 인증 정책을 강화하기 위해
Custom MAIL FROM을 사용할 수 있다.

예시:

```text
mail.pharmaflow.homes
```

이 경우 AWS SES가 제공하는 값에 따라 해당 MAIL FROM 전용 서브도메인에
MX 및 SPF TXT Record가 필요하다.

실제 AWS에서 생성되는 값은 구축 단계에서 확인하며
현재 문서에는 실제 DNS 값을 하드코딩하지 않는다.

---

## 12. 관리형 서비스와 직접 Mail Server 운영 비교

### 관리형 Mail Service

장점:

- Mail Server 직접 운영 불필요
- 스팸 필터 및 보안 관리 부담 감소
- Mailbox/웹메일/IMAP 등의 기능을 쉽게 사용할 수 있음
- 장애 및 업데이트 관리 부담 감소

단점:

- 사용자 또는 Mailbox 수에 따른 지속 비용 발생
- 외부 Mail Service 의존

### 직접 Mail Server 운영

예:

```text
EC2
 ↓
Postfix
 ↓
Dovecot
 ↓
Mailbox
```

장점:

- 시스템을 직접 제어 가능
- 교육 목적으로 Mail Server 구조를 경험할 수 있음

단점:

- SMTP 서버 운영 필요
- 스팸 및 악성 메일 대응 필요
- IP Reputation 관리 필요
- Reverse DNS 및 발신 신뢰도 관리 필요
- 보안 패치 및 장애 대응 필요
- 백업/복구 구성 필요
- 운영 난이도가 높음

PharmaFlow 프로젝트 규모에서는 이메일 자체가 핵심 서비스가 아니므로
직접 Mail Server를 구축하는 것보다 관리형 Mail Service를 사용하는 것을 권장한다.

---

## 13. 비용 및 구축 난이도

### Amazon SES

특징:

- 사용량 기반 이메일 발송 서비스
- 애플리케이션 자동 발신에 적합
- 프로젝트 규모에서는 발송량이 많지 않을 것으로 예상되어 비용 부담이 낮음

구축 난이도:

- 중간
- SES Domain Identity
- DKIM
- SMTP Credential
- 필요 시 Custom MAIL FROM 설정 필요

### 관리형 Mail Service

특징:

- Mailbox 기반 과금이 일반적
- admin / alerts 등의 실제 수신 주소 운영 가능
- 직접 Mail Server를 운영할 필요가 없음

구축 난이도:

- 낮음 ~ 중간
- Mail Service 가입
- Route53 MX/TXT Record 설정
- Mailbox/Alias 생성 필요

### 직접 Mail Server

특징:

- EC2 및 저장공간 비용 발생
- 지속적인 서버 운영 및 관리 필요

구축 난이도:

- 높음

따라서 비용뿐 아니라 구축 및 운영 인력까지 고려하면
SES + 관리형 Mailbox 조합이 현재 프로젝트에 가장 적합하다.

---

## 14. 최종 추천 구성

```text
[Django Application Mail]

Django
   ↓ SMTP
Amazon SES
   ↓
noreply@pharmaflow.homes
   ↓
사용자


[CloudWatch Alert]

CloudWatch
   ↓
SNS
   ↓
alerts@pharmaflow.homes
   ↓
운영 담당자


[Internet Mail]

Internet
   ↓
Route53 MX
   ↓
Managed Mail Service
   ├─ admin@pharmaflow.homes
   └─ alerts@pharmaflow.homes
```

역할별 추천:

| 주소 | 역할 | 추천 구성 |
|---|---|---|
| `noreply@pharmaflow.homes` | Django 자동 발신 | Amazon SES |
| `alerts@pharmaflow.homes` | CloudWatch/SNS 알림 수신 | Managed Mailbox |
| `admin@pharmaflow.homes` | 관리자 일반 송수신 | Managed Mailbox |

---

## 15. 향후 실제 구축 시 작업

실제 이메일 인프라 구축을 결정하면 다음 작업이 필요하다.

1. 관리형 Mail Service 선정
2. `admin@pharmaflow.homes` Mailbox 생성
3. `alerts@pharmaflow.homes` Mailbox 또는 Alias 생성
4. Route53 MX Record 구성
5. Amazon SES Domain Identity 생성
6. SES DKIM Record 구성
7. SPF 정책 구성
8. DMARC 정책 구성
9. 필요 시 SES Custom MAIL FROM 구성
10. Django SMTP 설정을 SES로 변경
11. SNS `alert_email`을 `alerts@pharmaflow.homes`로 변경
12. SNS Subscription Confirmation
13. Django 테스트 메일 발송
14. CloudWatch Alarm 테스트 알림 수신 확인

---

## 16. 이번 작업 범위

이번 작업에서는 이메일 인프라 조사 및 설계 문서만 작성한다.

수행하지 않는 작업:

- Route53 Record 변경
- SES 리소스 생성
- Mailbox 실제 생성
- SNS Subscription 변경
- Terraform Apply
- Django SMTP 실제 변경
- Nginx 설정 변경

특히 현재 운영 중인 Nginx 및 3-Tier 웹 서비스 구성은
이메일 인프라 조사와 독립적이므로 수정하지 않는다.
