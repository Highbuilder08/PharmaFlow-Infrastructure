variable "admin_cidr" {
  description = "Administrator public IP CIDR allowed to access Bastion"
  type        = string
}

variable "ec2_key_name" {
  description = "EC2 key pair name used for Bastion and private EC2 instances"
  type        = string
}