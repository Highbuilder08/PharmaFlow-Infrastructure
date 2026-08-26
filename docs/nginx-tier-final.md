# Nginx Web Tier — 최종 정리 (발표·검증용)

## 요약 — 한눈에

PharmaFlow의 Nginx Web Tier는 기존의 Django Base EC2 Private IP 직접 참조 구조에서 벗어나, **Public ALB → Nginx ASG → Internal ALB → Django ASG** 구조로 개선하였다.

Nginx는 Multi-AZ Auto Scaling Group으로 구성되며 Golden AMI v3와 Launch Template을 기반으로 동일한 서버 구성을 재생성할 수 있다.

Static 파일은 Django와 Nginx가 공유하는 EFS를 사용하며, Nginx가 `/static/` 요청을 직접 처리한다.

실제 장애시험에서는 Nginx 인스턴스 1대를 강제로 종료한 상황에서도 외부 서비스 HTTP 200 응답이 유지되었으며, Auto Scaling Group이 신규 Nginx 인스턴스를 자동 생성하여 최종적으로 Target Group이 다시 2/2 healthy 상태로 복구되는 것을 확인하였다.

---

## 1. 기존 문제 — Django Private IP 직접 참조

기존 Nginx 구성에서는 Django Base EC2의 Private IP를 직접 Backend 주소로 사용하였다.

이 구조에서는 Django 인스턴스가 Auto Scaling Group에 의해 교체되거나 재생성될 경우 Private IP가 변경될 수 있으며, Nginx 설정에 기록된 기존 IP와 실제 Django 인스턴스의 IP가 달라지는 문제가 발생할 수 있다.

따라서 Django ASG 환경에서는 특정 EC2 인스턴스의 Private IP에 직접 의존하는 구조가 적합하지 않았다.

---

## 2. 개선 구조 — Public ALB → Nginx ASG → Internal ALB → Django ASG

최종 요청 흐름은 다음과 같다.

```text
Client
  ↓
Public ALB
  ↓
Nginx ASG
  ↓
Internal ALB
  ↓
Django ASG
```

Nginx는 더 이상 특정 Django EC2의 Private IP를 참조하지 않는다.

기존 `django_private_ip` 기반 설정을 제거하고 Internal ALB의 DNS를 Backend 주소로 사용하도록 변경하였다.

```yaml
nginx_backend_host: "{{ internal_alb_dns }}"
nginx_backend_port: 80
```

Nginx 설정에서는 다음과 같이 변수화된 Backend를 사용한다.

```nginx
proxy_pass http://{{ nginx_backend_host }}:{{ nginx_backend_port }};
```

이에 따라 Django ASG 내부 인스턴스가 교체되더라도 Nginx 설정을 수정할 필요가 없으며, Internal ALB가 정상 Django 인스턴스로 요청을 전달한다.

---

## 3. Nginx ASG / Multi-AZ

Nginx Web Tier는 단일 EC2 인스턴스가 아니라 Auto Scaling Group 기반으로 구성하였다.

Nginx 인스턴스는 다음 두 Availability Zone에 분산된다.

* `ap-northeast-2a`
* `ap-northeast-2c`

이를 통해 하나의 Nginx 인스턴스에 장애가 발생하더라도 다른 정상 인스턴스를 통해 서비스 요청을 처리할 수 있도록 구성하였다.

Public ALB는 Nginx Target Group의 Health Check 결과를 기준으로 정상 상태의 Nginx 인스턴스에 요청을 전달한다.

---

## 4. Golden AMI v3 / Launch Template

Nginx ASG 인스턴스는 Golden AMI v3와 Launch Template을 기반으로 생성된다.

ASG 환경에서는 기존 Base EC2의 설정을 수정하는 것만으로 실행 중인 ASG 인스턴스 전체에 변경 사항이 자동 반영되지 않는다.

따라서 Nginx 설정 변경 후에는 검증된 상태를 Golden AMI로 생성하고 Launch Template에 새로운 AMI를 적용한 뒤 ASG 인스턴스를 교체하는 방식으로 배포하였다.

이 구조를 통해 신규 인스턴스가 생성되더라도 동일한 Nginx 설정과 필요한 구성 요소를 가진 서버를 자동으로 재생성할 수 있다.

---

## 5. Shared Static — EFS와 `/static/` Alias

Django와 Nginx가 각각 독립적인 Auto Scaling Group으로 동작하기 때문에 특정 EC2 인스턴스의 로컬 디스크에 저장된 Static 파일을 서로 공유할 수 없다.

이를 해결하기 위해 공용 EFS를 사용하였다.

Django의 `collectstatic` 결과는 다음 Shared Static 경로에 저장된다.

```text
/srv/pharmaflow/static/staticfiles/
```

Nginx ASG 인스턴스도 동일한 EFS를 마운트하고 `/static/` 요청을 해당 경로에서 직접 제공한다.

```nginx
location /static/ {
    alias /srv/pharmaflow/static/staticfiles/;
}
```

이를 통해 Nginx 인스턴스가 교체되더라도 동일한 Static 파일을 사용할 수 있다.

외부에서 logo 및 CSS 등의 Static 리소스를 직접 요청하여 HTTP 200 응답이 반환되는 것을 확인하였다.

---

## 6. 실제 Nginx 장애시험 기록 — 2026-08-26

### 시험 목적

Nginx ASG 인스턴스 중 하나에 실제 장애가 발생했을 때 다음 항목을 검증하였다.

* 외부 서비스가 지속되는지
* Public ALB가 정상 Nginx 인스턴스로 요청을 우회하는지
* ASG가 종료된 인스턴스를 자동으로 대체하는지
* 신규 인스턴스가 정상적으로 Target Group에 등록되는지
* Multi-AZ 구성이 다시 복구되는지
* Target Group이 최종적으로 2/2 healthy 상태가 되는지

### 시험 전 상태

시험 전 Nginx ASG는 정상 Nginx 인스턴스 2대를 유지하고 있었다.

두 인스턴스는 `ap-northeast-2a`와 `ap-northeast-2c`에 각각 분산되어 있었으며 Nginx Target Group은 2/2 healthy 상태였다.

### Nginx 인스턴스 1대 강제 종료

검증 과정에서 Nginx ASG에 포함된 인스턴스 1대를 실제로 종료하였다.

인스턴스가 종료된 이후에도 외부 서비스 요청을 반복 확인한 결과:

```text
site=200
```

응답이 계속 유지되었다.

Public ALB가 남아 있는 정상 Nginx 인스턴스를 통해 서비스 요청을 계속 처리하여 단일 Nginx 인스턴스 장애 상황에서도 서비스가 유지되는 것을 확인하였다.

### ASG 자동복구

Nginx ASG는 Desired Capacity 2를 유지하도록 구성되어 있기 때문에 인스턴스 1대가 종료되자 새로운 Nginx 인스턴스를 자동으로 생성하였다.

신규 인스턴스는 Nginx Golden AMI v3 기반 Launch Template을 사용하여 생성되었다.

별도의 수동 Nginx 설치 및 설정 작업 없이 기존 Web Tier와 동일한 구성의 신규 서버가 생성되는 것을 확인하였다.

### Multi-AZ 재구성

신규 인스턴스 생성 이후 Nginx ASG는 다시 다음 두 Availability Zone에 인스턴스를 분산시켰다.

```text
ap-northeast-2a
ap-northeast-2c
```

따라서 장애 발생 이후에도 최종적으로 Multi-AZ 구조가 복원되었다.

### Target Group 복구

종료된 기존 Target은 Target Group에서 `draining` 상태를 거친 뒤 제거되었다.

신규 Nginx 인스턴스는 Target Group에 등록된 후 Health Check를 통과하여 `healthy` 상태가 되었다.

최종 결과:

```text
Nginx Target Group
2/2 healthy
```

상태로 복구되었다.

### 장애시험 최종 판정

실제 Nginx 인스턴스 1대를 강제로 종료한 상황에서도 다음 항목을 확인하였다.

* 외부 서비스 HTTP 200 유지
* Public ALB를 통한 정상 Nginx 서비스 지속
* ASG 신규 Nginx 자동 생성
* Golden AMI v3 기반 서버 복원
* Multi-AZ 구조 재구성
* 기존 Target draining 후 제거
* 신규 Target healthy 등록
* Target Group 최종 2/2 healthy

따라서 Nginx Web Tier에서 단일 인스턴스 장애가 발생하더라도 서비스가 지속되고 ASG가 자동으로 정상 상태를 복구할 수 있음을 실제 시험으로 검증하였다.

---

## 7. CloudWatch / SNS와 실제 장애시험의 관계

Nginx Web Tier에는 Target Group의 `HealthyHostCount`를 기준으로 하는 CloudWatch Alarm이 구성되어 있다.

Nginx 인스턴스 장애 시 Healthy Target 수가 감소하면 CloudWatch Alarm의 평가 대상이 된다.

다만 이번 실제 장애시험에서는 ASG의 신규 인스턴스 생성과 Target Group 복구가 빠르게 진행되었기 때문에 CloudWatch Alarm의 평가기간과 실제 장애 지속시간의 관계를 함께 고려해야 한다.

일시적으로 HealthyHostCount가 감소하더라도 설정된 평가 조건을 충족하기 전에 정상 상태로 복구된다면 Alarm 상태 전환이 발생하지 않을 수 있다.

SNS의 ALARM 및 OK 이메일 전달 기능 자체는 별도의 CloudWatch/SNS 시험을 통해 정상 동작을 검증하였다.

---

## 8. Troubleshooting ① Django 고정 IP 의존 제거

### 문제

Nginx Backend가 특정 Django Base EC2의 Private IP를 직접 참조하였다.

### 원인

Auto Scaling 환경에서 EC2 인스턴스는 교체될 수 있으며 새로운 인스턴스에는 새로운 Private IP가 할당된다.

### 해결

`django_private_ip` 의존을 제거하고 `internal_alb_dns`를 Backend 주소로 사용하였다.

### 결과

Django ASG 내부 인스턴스 변경 여부와 관계없이 Nginx는 동일한 Internal ALB 주소를 사용할 수 있게 되었다.

---

## 9. Troubleshooting ② Base EC2 수정이 ASG에 바로 반영되지 않는 문제

### 문제

Base EC2에서 Nginx 설정을 수정했지만 ASG 인스턴스에는 해당 변경 사항이 바로 반영되지 않았다.

### 원인

Auto Scaling Group 인스턴스는 Launch Template에서 지정된 AMI를 기반으로 생성되기 때문에 Base EC2를 수정하는 것만으로 ASG 인스턴스의 기준 이미지가 변경되지 않는다.

### 해결

수정 및 검증된 Nginx 상태를 Golden AMI v3로 생성하고 Launch Template을 갱신하였다.

이후 Rolling Refresh 방식으로 ASG 인스턴스를 새로운 AMI 기반으로 교체하였다.

### 결과

Nginx ASG 전체가 동일한 최신 서버 구성을 사용할 수 있게 되었다.

---

## 10. Troubleshooting ③ 3-Tier 전환 이후 Static 404

### 문제

Nginx와 Django를 각각 독립된 ASG로 분리한 이후 Static 파일 요청에서 HTTP 404가 발생하였다.

### 원인

Django에서 생성된 `staticfiles`가 Django 인스턴스의 로컬 파일시스템에 존재했으며 별도의 Nginx ASG 인스턴스에서는 해당 파일에 접근할 수 없었다.

### 해결

Django와 Nginx가 함께 사용할 수 있는 Shared Static EFS를 구성하였다.

Django의 `collectstatic` 결과를 EFS에 저장하고 Nginx가 동일한 EFS를 마운트하도록 변경하였다.

Nginx의 `/static/` 요청에는 다음 경로를 alias로 적용하였다.

```text
/srv/pharmaflow/static/staticfiles/
```

### 결과

Nginx ASG의 어떤 인스턴스에서도 동일한 Static 파일을 제공할 수 있게 되었으며 외부 logo와 CSS 요청에서 HTTP 200 응답을 확인하였다.

---

## 최종 검증 요약

Nginx Web Tier의 최종 구조는 다음과 같다.

```text
Internet
   ↓
Public ALB
   ↓
Nginx ASG
(ap-northeast-2a / ap-northeast-2c)
   ↓
Internal ALB
   ↓
Django ASG
```

최종적으로 다음 항목을 확인하였다.

* Django Private IP 직접 의존 제거
* Internal ALB DNS 기반 Nginx Backend 구성
* Nginx Multi-AZ ASG 구성
* Golden AMI v3 / Launch Template 기반 서버 생성
* Shared Static EFS 구성
* `/static/` Alias 정상 동작
* 외부 Static 요청 HTTP 200
* Nginx 인스턴스 1대 실제 종료
* 장애 중 외부 서비스 HTTP 200 유지
* Public ALB를 통한 정상 Nginx 서비스 지속
* ASG 신규 Nginx 자동 생성
* 신규 Nginx Golden AMI v3 적용
* `ap-northeast-2a` / `ap-northeast-2c` Multi-AZ 복구
* 기존 Target draining 후 제거
* Nginx Target Group 최종 2/2 healthy
* CloudWatch HealthyHostCount Alarm 구성
* SNS ALARM/OK 이메일 별도 검증

이를 통해 PharmaFlow의 Nginx Web Tier가 특정 EC2 인스턴스의 IP나 로컬 파일에 의존하지 않고, 장애 상황에서도 서비스 지속과 자동복구가 가능한 구조로 개선되었음을 확인하였다.
