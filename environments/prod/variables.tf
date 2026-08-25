variable "admin_cidr" {
  description = "Administrator public IP CIDR allowed to access Bastion"
  type        = string
}

variable "ec2_key_name" {
  description = "EC2 key pair name used for Bastion and private EC2 instances"
  type        = string
}

variable "db_name" {
  description = "Initial database name for PharmaFlow"
  type        = string
}

variable "db_username" {
  description = "Master username for PharmaFlow RDS"
  type        = string
}

variable "db_password" {
  description = "Master password for PharmaFlow RDS"
  type        = string
  sensitive   = true
}

variable "domain_name" {
  description = "Primary domain name for PharmaFlow"
  type        = string
}

variable "alert_email" {
  description = "Email address for CloudWatch alarm notifications"
  type        = string
  sensitive   = true
}
