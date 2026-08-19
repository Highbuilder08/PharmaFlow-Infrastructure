variable "admin_cidr" {
  description = "Administrator public IP CIDR allowed to access Bastion"
  type        = string
}

variable "key_name" {
  description = "EC2 Key Pair name for SSH access (Bastion / Nginx / Django)"
  type        = string

  # Bastion 에 이미 쓰고 있는 키페어 이름.
  # default 를 둬야 기존 terraform.tfvars 를 고치지 않아도 plan 이 그대로 돕니다.
  default = "pharmaflow-infra-key"
}
