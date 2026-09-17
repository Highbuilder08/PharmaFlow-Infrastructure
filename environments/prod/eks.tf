# ---------------------------------------------------------
# PharmaFlow Amazon EKS Cluster
# ---------------------------------------------------------

resource "aws_eks_cluster" "pharmaflow" {
  name     = "pharmaflow-eks"
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids = [
      aws_subnet.app_private_a.id,
      aws_subnet.app_private_c.id
    ]

    endpoint_private_access = true
    endpoint_public_access  = true

  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]

  tags = {
    Name        = "pharmaflow-eks"
    Project     = "PharmaFlow"
    Environment = "prod"
    ManagedBy   = "Terraform"
  }
}


# ---------------------------------------------------------
# PharmaFlow EKS Managed Node Group
# ---------------------------------------------------------

resource "aws_eks_node_group" "pharmaflow" {
  cluster_name    = aws_eks_cluster.pharmaflow.name
  node_group_name = "pharmaflow-eks-nodes"
  node_role_arn   = aws_iam_role.eks_node.arn

  subnet_ids = [
    aws_subnet.app_private_a.id,
    aws_subnet.app_private_c.id
  ]

  instance_types = [
    "t3.small"
  ]

  capacity_type = "ON_DEMAND"

  scaling_config {
    desired_size = 2
    min_size     = 2
    max_size     = 4
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_worker_policy,
    aws_iam_role_policy_attachment.eks_node_ecr_policy,
    aws_iam_role_policy_attachment.eks_node_cni_policy
  ]

  tags = {
    Name        = "pharmaflow-eks-nodes"
    Project     = "PharmaFlow"
    Environment = "prod"
    ManagedBy   = "Terraform"
  }
}
