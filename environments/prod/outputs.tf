# ---------------------------------------------------------
# Terraform output
#
# Terraform 과 Ansible 은 자동 연동되지 않는다.
# 여기서 나온 값을 사람이 ansible/inventory/prod.local.ini 와
# ansible/group_vars/all/vars.yml 에 옮겨 적는다.
#
#   cd environments/prod && terraform output
#
# ⚠️ 저장소가 Public 이므로 여기서 나온 실제 IP 는
#    커밋되는 파일(prod.ini 등)에 적지 않는다.
# ---------------------------------------------------------

# ── Bastion ───────────────────────────────────────────────

output "bastion_public_ip" {
  description = "Elastic IP address of the Bastion host"
  value       = aws_eip.bastion.public_ip
}

output "bastion_private_ip" {
  description = "Private IP address of the Bastion host"
  value       = aws_instance.bastion.private_ip
}

# ── 애플리케이션 서버 ─────────────────────────────────────

output "django_base_private_ip" {
  description = "Django Base EC2 사설 IP → inventory 의 [django] ansible_host"
  value       = aws_instance.django_base.private_ip
}

# ── 네트워크 (RDS/EFS/ASG 구성 시 사용) ───────────────────

output "vpc_id" {
  description = "PharmaFlow VPC ID"
  value       = aws_vpc.pharmaflow.id
}

output "private_subnet_ids" {
  description = "Private Subnet A/C ID"
  value = {
    a = aws_subnet.private_a.id
    c = aws_subnet.private_c.id
  }
}

# ── NAT ───────────────────────────────────────────────

output "nat_public_ip" {
  description = "Elastic IP address of the NAT instance"
  value       = aws_eip.nat.public_ip
}

# ── Nginx ───────────────────────────────────────────────

output "nginx_base_private_ip" {
  description = "Private IP address of the Nginx base instance"
  value       = aws_instance.nginx.private_ip
}

# ── RDS ───────────────────────────────────────────────

output "rds_endpoint" {
  description = "RDS MariaDB endpoint"
  value       = aws_db_instance.pharmaflow.address
}

output "rds_port" {
  description = "RDS MariaDB port"
  value       = aws_db_instance.pharmaflow.port
}

# ── EFS ───────────────────────────────────────────────

output "efs_id" {
  description = "PharmaFlow EFS file system ID"
  value       = aws_efs_file_system.pharmaflow.id
}

output "efs_dns_name" {
  description = "PharmaFlow EFS DNS name"
  value       = aws_efs_file_system.pharmaflow.dns_name
}

# ── ALB ───────────────────────────────────────────────

output "internal_alb_dns_name" {
  description = "Internal ALB DNS name"
  value       = aws_lb.internal.dns_name
}

output "public_alb_dns_name" {
  description = "Public ALB DNS name"
  value       = aws_lb.public.dns_name
}

# ── AMI ───────────────────────────────────────────────

output "django_golden_ami_id" {
  description = "Golden AMI ID for Django"
  value       = aws_ami_from_instance.django_golden.id
}

output "django_golden_ami_v2_id" {
  description = "Django Golden AMI v2 ID"
  value       = aws_ami_from_instance.django_golden_v2.id
}

output "django_golden_ami_v3_id" {
  description = "Django Golden AMI v3 ID"
  value       = aws_ami_from_instance.django_golden_v3.id
}

output "django_golden_ami_v4_id" {
  description = "Django Golden AMI v4 ID"
  value       = aws_ami_from_instance.django_golden_v4.id
}

output "django_golden_ami_v5_id" {
  description = "Django Golden AMI v5 ID"
  value       = aws_ami_from_instance.django_golden_v5.id
}

output "nginx_golden_ami_id" {
  description = "Golden AMI ID for Nginx"
  value       = aws_ami_from_instance.nginx_golden.id
}

output "nginx_golden_ami_v2_id" {
  description = "Nginx Golden AMI v2 ID"
  value       = aws_ami_from_instance.nginx_golden_v2.id
}

output "nginx_golden_ami_v3_id" {
  description = "Nginx Golden AMI v3 ID"
  value       = aws_ami_from_instance.nginx_golden_v3.id
}

# ── Launch_Template ───────────────────────────────────────────────

output "django_launch_template_id" {
  description = "Django Launch Template ID"
  value       = aws_launch_template.django.id
}

output "nginx_launch_template_id" {
  description = "Nginx Launch Template ID"
  value       = aws_launch_template.nginx.id
}

# ── Django ASG ───────────────────────────────────────────────

output "django_asg_name" {
  description = "Django Auto Scaling Group name"
  value       = aws_autoscaling_group.django.name
}

# ── Route53 ───────────────────────────────────────────────

output "route53_name_servers" {
  description = "Route53 authoritative name servers"
  value       = aws_route53_zone.pharmaflow.name_servers
}

# ── WireGuard Hybrid VPN ──────────────────────────────────

output "wireguard_public_ip" {
  description = "Elastic IP address of the WireGuard VPN gateway"
  value       = aws_eip.wireguard.public_ip
}

output "wireguard_private_ip" {
  description = "Private IP address of the WireGuard VPN gateway"
  value       = aws_instance.wireguard.private_ip
}

# ── Amazon SES ────────────────────────────────────────────

output "ses_domain_identity" {
  description = "Amazon SES verified domain identity"
  value       = aws_sesv2_email_identity.pharmaflow.email_identity
}

output "ses_verification_status" {
  description = "Amazon SES domain verification status"
  value       = aws_sesv2_email_identity.pharmaflow.verification_status
}

output "ses_dkim_status" {
  description = "Amazon SES DKIM status"
  value       = aws_sesv2_email_identity.pharmaflow.dkim_signing_attributes[0].status
}
