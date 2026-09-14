# ---------------------------------------------------------
# Django Base EC2 (팀원2 담당)
#
# 목적: Ansible django role 을 적용할 기준 서버 1대.
#       이 서버를 검증한 뒤 AMI 로 구워서 ASG 로 확장한다.
#
# 배치: Private Subnet A (10.23.11.0/24)
#       - Public IP 없음 (관리 접근은 Bastion 경유)
#       - 아웃바운드는 Private Route Table → NAT Instance 로 나간다
#         (apt / git clone / pip 가 이 경로를 쓴다)
#
# AMI: nat.tf 의 data.aws_ami.ubuntu 를 그대로 재사용한다.
#      (Ubuntu 24.04 Noble — Django 6.0 이 Python 3.12+ 를 요구하므로 22.04 는 불가)
# ---------------------------------------------------------

resource "aws_instance" "django_base" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.private_a.id
  vpc_security_group_ids      = [aws_security_group.django.id]
  associate_public_ip_address = false
  key_name                    = var.ec2_key_name

  # IMDSv2 강제 (Base AMI 로 구워질 서버이므로 처음부터 적용)
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  # user_data 를 쓰지 않는다.
  # 서버 안을 채우는 일은 전부 Ansible django role 이 담당한다.
  # (Terraform = 서버 생성 / Ansible = 서버 구성)

  tags = {
    Name        = "pharmaflow-django-base"
    Project     = "PharmaFlow"
    Environment = "prod"
    Role        = "django"
  }
}
