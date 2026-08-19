resource "aws_efs_file_system" "pharmaflow" {
  creation_token = "pharmaflow-efs"
  encrypted      = true

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name        = "pharmaflow-efs"
    Project     = "PharmaFlow"
    Environment = "prod"
  }
}

resource "aws_efs_mount_target" "private_a" {
  file_system_id  = aws_efs_file_system.pharmaflow.id
  subnet_id       = aws_subnet.private_a.id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_mount_target" "private_c" {
  file_system_id  = aws_efs_file_system.pharmaflow.id
  subnet_id       = aws_subnet.private_c.id
  security_groups = [aws_security_group.efs.id]
}
