# ---------------------------------------------------------
# EKS Pod Identity - EFS CSI Driver IAM Role
# ---------------------------------------------------------

resource "aws_iam_role" "eks_efs_csi" {
  name = "pharmaflow-eks-efs-csi-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "pods.eks.amazonaws.com"
        }

        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })

  tags = {
    Name        = "pharmaflow-eks-efs-csi-role"
    Project     = "PharmaFlow"
    Environment = "prod"
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "eks_efs_csi" {
  role       = aws_iam_role.eks_efs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
}
