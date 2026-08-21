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

# ---------------------------------------------------------
# Web Tier Private Subnets
# ---------------------------------------------------------

resource "aws_subnet" "web_private_a" {
  vpc_id                  = aws_vpc.pharmaflow.id
  cidr_block              = "10.23.21.0/24"
  availability_zone       = "ap-northeast-2a"
  map_public_ip_on_launch = false

  tags = {
    Name        = "pharmaflow-web-private-a"
    Project     = "PharmaFlow"
    Environment = "prod"
    Type        = "web-private"
    Tier        = "web"
  }
}

resource "aws_subnet" "web_private_c" {
  vpc_id                  = aws_vpc.pharmaflow.id
  cidr_block              = "10.23.22.0/24"
  availability_zone       = "ap-northeast-2c"
  map_public_ip_on_launch = false

  tags = {
    Name        = "pharmaflow-web-private-c"
    Project     = "PharmaFlow"
    Environment = "prod"
    Type        = "web-private"
    Tier        = "web"
  }
}

# ---------------------------------------------------------
# Application Tier Private Subnets
# ---------------------------------------------------------

resource "aws_subnet" "app_private_a" {
  vpc_id                  = aws_vpc.pharmaflow.id
  cidr_block              = "10.23.31.0/24"
  availability_zone       = "ap-northeast-2a"
  map_public_ip_on_launch = false

  tags = {
    Name        = "pharmaflow-app-private-a"
    Project     = "PharmaFlow"
    Environment = "prod"
    Type        = "app-private"
    Tier        = "application"
  }
}

resource "aws_subnet" "app_private_c" {
  vpc_id                  = aws_vpc.pharmaflow.id
  cidr_block              = "10.23.32.0/24"
  availability_zone       = "ap-northeast-2c"
  map_public_ip_on_launch = false

  tags = {
    Name        = "pharmaflow-app-private-c"
    Project     = "PharmaFlow"
    Environment = "prod"
    Type        = "app-private"
    Tier        = "application"
  }
}

# ---------------------------------------------------------
# Database Tier Private Subnets
# ---------------------------------------------------------

resource "aws_subnet" "db_private_a" {
  vpc_id                  = aws_vpc.pharmaflow.id
  cidr_block              = "10.23.41.0/24"
  availability_zone       = "ap-northeast-2a"
  map_public_ip_on_launch = false

  tags = {
    Name        = "pharmaflow-db-private-a"
    Project     = "PharmaFlow"
    Environment = "prod"
    Type        = "db-private"
    Tier        = "database"
  }
}

resource "aws_subnet" "db_private_c" {
  vpc_id                  = aws_vpc.pharmaflow.id
  cidr_block              = "10.23.42.0/24"
  availability_zone       = "ap-northeast-2c"
  map_public_ip_on_launch = false

  tags = {
    Name        = "pharmaflow-db-private-c"
    Project     = "PharmaFlow"
    Environment = "prod"
    Type        = "db-private"
    Tier        = "database"
  }
}
