# ---------------------------------------------------------
# Terraform output
#
# Terraform 과 Ansible 은 자동 연동되지 않는다.
# 여기서 나온 값을 사람이 ansible/inventory/prod.ini 와
# ansible/group_vars/all/vars.yml 에 옮겨 적는다.
#
#   cd environments/prod && terraform output
# ---------------------------------------------------------

output "vpc_id" {
  description = "PharmaFlow VPC ID"
  value       = aws_vpc.pharmaflow.id
}

output "private_subnet_ids" {
  description = "Private Subnet A/C ID (RDS/EFS/ASG 구성 시 사용)"
  value = {
    a = aws_subnet.private_a.id
    c = aws_subnet.private_c.id
  }
}

output "nat_public_ip" {
  description = "NAT Instance 공인 IP"
  value       = aws_instance.nat.public_ip
}

# ── Ansible 인벤토리에 옮겨 적을 값 ────────────────────────

output "django_base_private_ip" {
  description = "Django Base EC2 사설 IP → inventory/prod.ini 의 [django] ansible_host"
  value       = aws_instance.django_base.private_ip
}
