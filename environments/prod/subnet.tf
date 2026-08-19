resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.pharmaflow.id
  cidr_block              = "10.23.1.0/24"
  availability_zone       = "ap-northeast-2a"
  map_public_ip_on_launch = true

  tags = {
    Name        = "pharmaflow-public-a"
    Project     = "PharmaFlow"
    Environment = "prod"
    Type        = "public"
  }
}

resource "aws_subnet" "public_c" {
  vpc_id                  = aws_vpc.pharmaflow.id
  cidr_block              = "10.23.2.0/24"
  availability_zone       = "ap-northeast-2c"
  map_public_ip_on_launch = true

  tags = {
    Name        = "pharmaflow-public-c"
    Project     = "PharmaFlow"
    Environment = "prod"
    Type        = "public"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id                  = aws_vpc.pharmaflow.id
  cidr_block              = "10.23.11.0/24"
  availability_zone       = "ap-northeast-2a"
  map_public_ip_on_launch = false

  tags = {
    Name        = "pharmaflow-private-a"
    Project     = "PharmaFlow"
    Environment = "prod"
    Type        = "private"
  }
}

resource "aws_subnet" "private_c" {
  vpc_id                  = aws_vpc.pharmaflow.id
  cidr_block              = "10.23.12.0/24"
  availability_zone       = "ap-northeast-2c"
  map_public_ip_on_launch = false

  tags = {
    Name        = "pharmaflow-private-c"
    Project     = "PharmaFlow"
    Environment = "prod"
    Type        = "private"
  }
}
