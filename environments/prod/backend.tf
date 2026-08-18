terraform {
  backend "s3" {
    bucket       = "pharmaflow-terraform-state-962450756907"
    key          = "prod/terraform.tfstate"
    region       = "ap-northeast-2"
    profile      = "pharmaflow"
    encrypt      = true
    use_lockfile = true
  }
}
