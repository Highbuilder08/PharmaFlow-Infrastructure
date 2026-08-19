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
  description = "Public IP address of the Bastion host"
  value       = aws_instance.bastion.public_ip
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

output "nat_public_ip" {
  description = "NAT Instance 공인 IP"
  value       = aws_instance.nat.public_ip
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