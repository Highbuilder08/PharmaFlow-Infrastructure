# ---------------------------------------------------------
# EKS Pod Identity Agent
# ---------------------------------------------------------

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name = aws_eks_cluster.pharmaflow.name
  addon_name   = "eks-pod-identity-agent"

  depends_on = [
    aws_eks_node_group.pharmaflow
  ]

  tags = {
    Project     = "PharmaFlow"
    Environment = "prod"
    ManagedBy   = "Terraform"
  }
}


# ---------------------------------------------------------
# Amazon EFS CSI Driver
# ---------------------------------------------------------

resource "aws_eks_addon" "efs_csi" {
  cluster_name = aws_eks_cluster.pharmaflow.name
  addon_name   = "aws-efs-csi-driver"

  pod_identity_association {
    role_arn        = aws_iam_role.eks_efs_csi.arn
    service_account = "efs-csi-controller-sa"
  }

  depends_on = [
    aws_eks_addon.pod_identity_agent,
    aws_iam_role_policy_attachment.eks_efs_csi
  ]

  tags = {
    Project     = "PharmaFlow"
    Environment = "prod"
    ManagedBy   = "Terraform"
  }
}
