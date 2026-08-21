resource "aws_route_table" "public" {
  vpc_id = aws_vpc.pharmaflow.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.pharmaflow.id
  }

  tags = {
    Name        = "pharmaflow-public-rt"
    Project     = "PharmaFlow"
    Environment = "prod"
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_c" {
  subnet_id      = aws_subnet.public_c.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.pharmaflow.id

  tags = {
    Name        = "pharmaflow-private-rt"
    Project     = "PharmaFlow"
    Environment = "prod"
  }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_c" {
  subnet_id      = aws_subnet.private_c.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat.primary_network_interface_id
}

# ---------------------------------------------------------
# Web Tier Route Table
# ---------------------------------------------------------

resource "aws_route_table" "web_private" {
  vpc_id = aws_vpc.pharmaflow.id

  tags = {
    Name        = "pharmaflow-web-private-rt"
    Project     = "PharmaFlow"
    Environment = "prod"
    Tier        = "web"
  }
}

resource "aws_route" "web_private_nat" {
  route_table_id         = aws_route_table.web_private.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat.primary_network_interface_id
}

resource "aws_route_table_association" "web_private_a" {
  subnet_id      = aws_subnet.web_private_a.id
  route_table_id = aws_route_table.web_private.id
}

resource "aws_route_table_association" "web_private_c" {
  subnet_id      = aws_subnet.web_private_c.id
  route_table_id = aws_route_table.web_private.id
}

# ---------------------------------------------------------
# Application Tier Route Table
# ---------------------------------------------------------

resource "aws_route_table" "app_private" {
  vpc_id = aws_vpc.pharmaflow.id

  tags = {
    Name        = "pharmaflow-app-private-rt"
    Project     = "PharmaFlow"
    Environment = "prod"
    Tier        = "application"
  }
}

resource "aws_route" "app_private_nat" {
  route_table_id         = aws_route_table.app_private.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat.primary_network_interface_id
}

resource "aws_route_table_association" "app_private_a" {
  subnet_id      = aws_subnet.app_private_a.id
  route_table_id = aws_route_table.app_private.id
}

resource "aws_route_table_association" "app_private_c" {
  subnet_id      = aws_subnet.app_private_c.id
  route_table_id = aws_route_table.app_private.id
}

# ---------------------------------------------------------
# Database Tier Route Table
# No Internet default route
# ---------------------------------------------------------

resource "aws_route_table" "db_private" {
  vpc_id = aws_vpc.pharmaflow.id

  tags = {
    Name        = "pharmaflow-db-private-rt"
    Project     = "PharmaFlow"
    Environment = "prod"
    Tier        = "database"
  }
}

resource "aws_route_table_association" "db_private_a" {
  subnet_id      = aws_subnet.db_private_a.id
  route_table_id = aws_route_table.db_private.id
}

resource "aws_route_table_association" "db_private_c" {
  subnet_id      = aws_subnet.db_private_c.id
  route_table_id = aws_route_table.db_private.id
}
