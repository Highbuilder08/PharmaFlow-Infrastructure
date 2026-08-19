resource "aws_instance" "nginx" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private_a.id
  vpc_security_group_ids      = [aws_security_group.nginx.id]
  key_name                    = var.ec2_key_name
  associate_public_ip_address = false

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = {
    Name        = "pharmaflow-nginx"
    Project     = "PharmaFlow"
    Environment = "prod"
    Role        = "nginx"
  }
}