# ---------------------------------------------------------
# AWS Load Balancer Controller - Pod Identity IAM Role
# ---------------------------------------------------------

resource "aws_iam_role" "eks_lbc" {
  name = "pharmaflow-eks-load-balancer-controller-role"

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
    Name        = "pharmaflow-eks-load-balancer-controller-role"
    Project     = "PharmaFlow"
    Environment = "prod"
    ManagedBy   = "Terraform"
  }
}

# ---------------------------------------------------------
# AWS Load Balancer Controller IAM Policy
# ---------------------------------------------------------

resource "aws_iam_policy" "eks_lbc" {
  name        = "pharmaflow-eks-load-balancer-controller-policy"
  description = "IAM policy for PharmaFlow AWS Load Balancer Controller"

  policy = file("${path.module}/policies/aws-load-balancer-controller.json")

  tags = {
    Name        = "pharmaflow-eks-load-balancer-controller-policy"
    Project     = "PharmaFlow"
    Environment = "prod"
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "eks_lbc" {
  role       = aws_iam_role.eks_lbc.name
  policy_arn = aws_iam_policy.eks_lbc.arn
}

# ---------------------------------------------------------
# AWS Load Balancer Controller - Pod Identity Association
# ---------------------------------------------------------

resource "aws_eks_pod_identity_association" "lbc" {
  cluster_name    = aws_eks_cluster.pharmaflow.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.eks_lbc.arn

  depends_on = [
    aws_eks_addon.pod_identity_agent,
    aws_iam_role_policy_attachment.eks_lbc
  ]

  tags = {
    Project     = "PharmaFlow"
    Environment = "prod"
    ManagedBy   = "Terraform"
  }
}
