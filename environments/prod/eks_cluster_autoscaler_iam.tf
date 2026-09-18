# ---------------------------------------------------------
# Cluster Autoscaler - Pod Identity IAM Role
# ---------------------------------------------------------

resource "aws_iam_role" "eks_cluster_autoscaler" {
  name = "pharmaflow-eks-cluster-autoscaler-role"

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
    Name        = "pharmaflow-eks-cluster-autoscaler-role"
    Project     = "PharmaFlow"
    Environment = "prod"
    ManagedBy   = "Terraform"
  }
}

# ---------------------------------------------------------
# Cluster Autoscaler IAM Policy
# ---------------------------------------------------------

resource "aws_iam_policy" "eks_cluster_autoscaler" {
  name        = "pharmaflow-eks-cluster-autoscaler-policy"
  description = "Least-privilege AWS permissions for PharmaFlow Cluster Autoscaler"

  policy = file("${path.module}/policies/cluster-autoscaler.json")

  tags = {
    Name        = "pharmaflow-eks-cluster-autoscaler-policy"
    Project     = "PharmaFlow"
    Environment = "prod"
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_autoscaler" {
  role       = aws_iam_role.eks_cluster_autoscaler.name
  policy_arn = aws_iam_policy.eks_cluster_autoscaler.arn
}

# ---------------------------------------------------------
# Cluster Autoscaler - Pod Identity Association
# ---------------------------------------------------------

resource "aws_eks_pod_identity_association" "cluster_autoscaler" {
  cluster_name    = aws_eks_cluster.pharmaflow.name
  namespace       = "kube-system"
  service_account = "cluster-autoscaler"
  role_arn        = aws_iam_role.eks_cluster_autoscaler.arn

  depends_on = [
    aws_eks_addon.pod_identity_agent,
    aws_iam_role_policy_attachment.eks_cluster_autoscaler
  ]

  tags = {
    Project     = "PharmaFlow"
    Environment = "prod"
    ManagedBy   = "Terraform"
  }
}
