resource "aws_internet_gateway" "pharmaflow" {
  vpc_id = aws_vpc.pharmaflow.id

  tags = {
    Name        = "pharmaflow-igw"
    Project     = "PharmaFlow"
    Environment = "prod"
  }
}
