resource "aws_vpc" "pharmaflow" {
  cidr_block           = "10.23.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "pharmaflow-vpc"
    Project     = "PharmaFlow"
    Environment = "prod"
  }
}
