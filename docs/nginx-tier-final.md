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
Internet
  ↓
Route53 / WAF
  ↓
Public ALB
  ↓
Nginx ASG
  ↓
Internal ALB
  ↓
Django ASG
```

외부 요청은 Route53을 통해 서비스 도메인으로 유입되고, WAF와 Public ALB를 거쳐 Nginx Web Tier로 전달된다.

Nginx는 더 이상 특정 Django EC2의 Private IP를 참조하지 않는다.

기존 django_private_ip 기반 설정을 제거하고 Internal ALB의 DNS를 Backend 주소로 사용하도록 변경하였다.

```yaml
nginx_backend_host: "{{ internal_alb_dns }}"
nginx_backend_port: 80
```

Nginx 설정에서는 다음과 같이 변수화된 Backend를 사용한다.

```nginx
proxy_pass http://{{ nginx_backend_host }}:{{ nginx_backend_port }};
```

Nginx에서 Django까지의 실제 Backend 요청 흐름은 다음과 같다.
```nginx
  → Internal ALB:80
  → Django ASG:8000
```

Nginx는 개별 Django 인스턴스의 IP를 알 필요가 없으며, Internal ALB가 Health Check를 통과한 정상 Django ASG 인스턴스로 요청을 전달한다.

따라서 Django ASG에서 인스턴스가 교체되어 Private IP가 변경되더라도 Nginx Backend 설정을 다시 변경할 필요가 없다.

---

## 3. Nginx ASG / Multi-AZ

Nginx Web Tier는 단일 EC2 인스턴스가 아니라 Auto Scaling Group 기반으로 구성하였다.

Nginx 인스턴스는 다음 두 Availability Zone에 분산된다.

* `ap-northeast-2a`
* `ap-northeast-2c`

이를 통해 하나의 Nginx 인스턴스에 장애가 발생하더라도 다른 정상 인스턴스를 통해 서비스 요청을 처리할 수 있도록 구성하였다.

Public ALB는 Nginx Target Group의 Health Check 결과를 기준으로 정상 상태의 Nginx 인스턴스에 요청을 전달한다.

---

## 4. Golden AMI v3 / Launch Template Version 3

최종 Nginx Web Tier는 다음 구성으로 운영된다.

- Nginx Golden AMI v3
- Launch Template Version 3
- Nginx ASG 인스턴스 2대
- `ap-northeast-2a` / `ap-northeast-2c` Multi-AZ
- Public ALB Target Group 연동

ASG 환경에서는 기존 Base EC2의 설정을 수정하는 것만으로 실행 중인 ASG 인스턴스 전체에 변경 사항이 자동 반영되지 않는다.

따라서 Nginx 설정 변경 후 검증된 서버 상태를 Golden AMI로 생성하고, Launch Template에 새로운 AMI를 적용한 뒤 Rolling Refresh를 통해 ASG 인스턴스를 교체하였다.

현재 사용 중인 Golden AMI v3에는 Nginx 설정뿐만 아니라 Shared Static EFS Mount 및 Nginx `/static/` 제공에 필요한 설정도 포함되어 있다.

Rolling Refresh 완료 후 실제 운영 중인 Nginx ASG 인스턴스 2대가 모두 Golden AMI v3를 사용하는 것을 확인하였다.

이를 통해 기존 인스턴스가 종료되거나 장애로 교체되더라도 Launch Template Version 3과 Golden AMI v3를 기반으로 동일한 Web Tier 구성을 가진 신규 Nginx 인스턴스를 자동으로 생성할 수 있도록 하였다.

---

## 5. Shared Static — EFS와 `/static/` Alias

3-Tier 구조에서는 Django와 Nginx가 각각 독립적인 Auto Scaling Group으로 동작하기 때문에 특정 EC2 인스턴스의 로컬 디스크에 저장된 Static 파일을 서로 공유할 수 없다.

3-Tier 전환 이후 Django의 `collectstatic` 결과가 Django 인스턴스의 로컬 `staticfiles`에 저장되면서, 별도의 Nginx EC2/ASG에서는 해당 파일에 접근할 수 없어 `/static/*` 요청에서 HTTP 404 문제가 발생하였다.

이를 해결하기 위해 Django와 Nginx가 함께 사용하는 Shared Static EFS 구조를 적용하였다.

최종 Static 처리 흐름은 다음과 같다.

```text
Django collectstatic
  ↓
EFS Shared Static
  ↓
Nginx EFS Mount
  ↓
location /static/
  ↓
Nginx 직접 제공
```

Django의 collectstatic 결과는 다음 Shared Static 경로에 저장된다.
```
/srv/pharmaflow/static/staticfiles/
```

Nginx ASG 인스턴스도 동일한 EFS를 마운트하고 /static/ 요청을 해당 경로에서 직접 제공한다.
```nginx
location /static/ {
    alias /srv/pharmaflow/static/staticfiles/;
}
```

따라서 Nginx 인스턴스가 교체되더라도 EFS에 저장된 동일한 Static 파일을 계속 제공할 수 있다.

실제 외부 요청을 통해 다음 Static 리소스와 메인 페이지의 HTTP 응답을 검증하였다.

```
/static/images/logo.png       → HTTP 200
/static/images/logo_full.png  → HTTP 200
/static/css/style.css         → HTTP 200
메인 페이지                  → HTTP 200
```

이를 통해 Django와 Nginx가 서로 다른 ASG 인스턴스로 동작하는 환경에서도 Static 파일을 공유하고 정상적으로 제공할 수 있음을 확인하였다.

또한 Nginx ASG Rolling Refresh 이후 실제 운영 인스턴스 2대가 모두 Shared Static 설정이 포함된 Golden AMI v3를 사용하는 것을 확인하였다.

---

## 6. 실제 Nginx 장애시험 기록 — 2026-08-26

### 시험 목적

2026-08-26 실제 AWS 환경에서 Nginx ASG 인스턴스 중 하나를 강제로 종료하여 단일 Nginx 인스턴스 장애 상황을 발생시키고, 서비스 지속성과 Auto Scaling 자동복구가 실제로 정상 동작하는지 검증하였다.

### 주요 검증 항목

- Nginx 인스턴스 1대 종료 시에도 외부 서비스가 지속되는지 확인
- Public ALB가 남아 있는 정상 Nginx 인스턴스를 통해 요청을 처리하는지 확인
- 종료된 Target이 `draining` 상태로 전환되는지 확인
- ASG가 Desired Capacity를 유지하기 위해 신규 Nginx 인스턴스를 자동 생성하는지 확인
- 신규 인스턴스가 Golden AMI v3 기반으로 생성되는지 확인
- `ap-northeast-2a` / `ap-northeast-2c` Multi-AZ 구성이 다시 복구되는지 확인
- 신규 인스턴스가 Public ALB Target Group에 등록되어 `healthy` 상태가 되는지 확인
- Target Group이 최종적으로 2/2 healthy 상태로 복구되는지 확인

### 시험 전 정상 상태

장애시험 전 Nginx ASG는 정상 Nginx 인스턴스 2대를 유지하고 있었다.

### Availability Zone 배치

- `ap-northeast-2a` → Nginx 인스턴스 1대
- `ap-northeast-2c` → Nginx 인스턴스 1대
- Public ALB Nginx Target Group → 2/2 healthy
- 외부 서비스 → HTTP 200

두 인스턴스 모두 Public ALB의 Nginx Target Group에서 `healthy` 상태인 것을 확인한 뒤 장애시험을 진행하였다.

### Nginx 인스턴스 1대 강제 종료

정상 Nginx ASG 인스턴스 2대 중 `ap-northeast-2a`에서 실행 중이던 Nginx 인스턴스 1대를 실제로 강제 종료하였다.

### 종료 직후 관측 결과

- `ap-northeast-2a` Nginx 인스턴스 종료
- 종료 대상 Target이 Target Group에서 `draining` 상태로 전환
- `ap-northeast-2c`의 정상 Nginx 인스턴스는 계속 요청 처리
- 장애 발생 중 외부 서비스 HTTP 200 유지

외부 서비스 요청을 지속적으로 확인한 결과 다음 응답이 유지되었다.

```text
site=200
```

따라서 Nginx 인스턴스 1대가 실제로 종료된 상황에서도 전체 서비스 장애는 발생하지 않았다.

Public ALB가 남아 있는 `ap-northeast-2c`의 정상 Nginx 인스턴스를 통해 트래픽을 계속 처리하면서 외부 서비스 HTTP 200이 유지되는 것을 확인하였다.

### ASG 신규 Nginx 자동 생성

Nginx ASG는 정상 인스턴스 2대를 유지하도록 구성되어 있다.

`ap-northeast-2a`의 기존 Nginx 인스턴스가 종료되자 ASG가 부족해진 인스턴스를 감지하고 신규 Nginx 인스턴스 1대를 자동으로 생성하였다.

### 신규 인스턴스 구성

- Launch Template Version 3 사용
- Nginx Golden AMI v3 사용
- 별도의 수동 EC2 생성 작업 없음
- 별도의 수동 Nginx 재설치 작업 없음
- Golden AMI에 포함된 Nginx 설정을 기반으로 환경 복원
- Shared Static EFS 및 `/static/` 제공 설정을 포함한 환경 복원

이를 통해 Golden AMI와 Launch Template을 이용한 Nginx Web Tier 자동복구가 실제 환경에서도 정상 동작함을 확인하였다.

### Multi-AZ 재구성

ASG가 생성한 신규 Nginx 인스턴스는 다시 `ap-northeast-2a`에 배치되었다.

복구 이후 구성은 다음과 같다.

- `ap-northeast-2a` → 신규 Nginx 인스턴스 / Golden AMI v3
- `ap-northeast-2c` → 기존 정상 Nginx 인스턴스
- Nginx ASG → 다시 2대 구성
- Multi-AZ → 정상 복구

기존 `ap-northeast-2c` 인스턴스가 서비스를 유지하는 동안 ASG가 `ap-northeast-2a`에 신규 인스턴스를 생성하여 Nginx 2대 / Multi-AZ 구조를 자동으로 복구하였다.

### Target Group 복구

강제 종료된 기존 Nginx Target은 deregistration 과정에서 `draining` 상태로 전환되었으며, draining 완료 후 Target Group에서 제거되었다.

ASG가 새롭게 생성한 Nginx 인스턴스는 Public ALB의 Nginx Target Group에 자동으로 등록되었다.

신규 인스턴스는 Health Check를 통과한 뒤 `healthy` 상태로 전환되었다.

### 최종 Target Group 상태

- 기존 종료 Target → `draining` 후 제거
- 신규 Nginx Target → `healthy`
- 기존 정상 Nginx Target → `healthy`
- 최종 Nginx Target Group → 2/2 healthy

이를 통해 신규 인스턴스 생성부터 Target Group 등록, Health Check 통과 및 최종 2/2 healthy 복구까지 전체 자동복구 과정이 정상적으로 완료되었음을 확인하였다.

### 실제 장애 및 복구 흐름

```text
ap-northeast-2a Nginx 인스턴스 강제 종료
  ↓
종료 Target draining
  ↓
Public ALB가 ap-northeast-2c 정상 Nginx를 통해 요청 처리
  ↓
외부 서비스 HTTP 200 유지
  ↓
ASG 신규 Nginx 인스턴스 자동 생성
  ↓
Launch Template Version 3 / Golden AMI v3 기반 환경 복원
  ↓
신규 인스턴스 ap-northeast-2a 배치
  ↓
ap-northeast-2a / ap-northeast-2c Multi-AZ 재구성
  ↓
신규 Target Health Check 통과
  ↓
신규 Target healthy 전환
  ↓
기존 Target deregistration/draining 완료 후 제거
  ↓
Nginx Target Group 최종 2/2 healthy
```

### 장애시험 최종 판정

2026-08-26 실제 AWS 환경에서 다음 항목을 검증하였다.

- Nginx 인스턴스 1대 실제 강제 종료
- 장애 발생 중 외부 서비스 HTTP 200 유지
- Public ALB를 통한 정상 Nginx 트래픽 처리
- 종료 Target의 `draining` 전환
- ASG 신규 Nginx 인스턴스 자동 생성
- Launch Template Version 3 적용
- 신규 인스턴스 Golden AMI v3 적용
- 신규 인스턴스 `ap-northeast-2a` 배치
- 기존 `ap-northeast-2c` 인스턴스와 Multi-AZ 구조 복구
- 신규 Target `healthy` 전환
- 기존 Target deregistration/draining 완료 후 제거
- Nginx Target Group 최종 2/2 healthy

따라서 실제 Nginx 인스턴스 1대가 종료되는 장애 상황에서도 Public ALB가 정상 Nginx 인스턴스를 통해 서비스를 지속하고, ASG가 Golden AMI v3 기반 신규 인스턴스를 자동 생성하여 Multi-AZ 및 Target Group 정상 상태까지 복구하는 것을 실제 장애시험으로 검증하였다.

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


## 발표 예상 질문
- 왜 Nginx 앞에 ALB가 필요한가?
- 왜 Nginx 뒤에 Internal ALB가 또 필요한가?
- 왜 Nginx도 ASG로 구성했는가?
- 왜 Static을 EFS에 저장했는가?
- Nginx 1대 장애 시 서비스가 어떻게 유지되는가?
- Golden AMI와 Launch Template의 역할 차이는?
- 장애가 발생했는데 CloudWatch ALARM이 항상 발생하지 않을 수도 있는 이유는?