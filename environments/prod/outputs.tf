output "bastion_public_ip" {
  description = "Public IP address of the Bastion host"
  value       = aws_instance.bastion.public_ip
}

output "bastion_private_ip" {
  description = "Private IP address of the Bastion host"
  value       = aws_instance.bastion.private_ip
}
