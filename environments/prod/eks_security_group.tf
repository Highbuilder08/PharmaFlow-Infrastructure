# ---------------------------------------------------------
# EKS Cluster Security Group -> RDS MariaDB
#
# Amazon EKS가 자동으로 생성하는 Cluster Security Group을
# RDS 접근 Source Security Group으로 사용한다.
# ---------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "rds_from_eks" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_eks_cluster.pharmaflow.vpc_config[0].cluster_security_group_id

  from_port   = 3306
  to_port     = 3306
  ip_protocol = "tcp"

  description = "Allow MariaDB access from PharmaFlow EKS"
}


# ---------------------------------------------------------
# EKS Cluster Security Group -> EFS
#
# EKS Worker Node에서 기존 PharmaFlow EFS의
# NFS 2049 포트에 접근할 수 있도록 허용한다.
# ---------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "efs_from_eks" {
  security_group_id            = aws_security_group.efs.id
  referenced_security_group_id = aws_eks_cluster.pharmaflow.vpc_config[0].cluster_security_group_id

  from_port   = 2049
  to_port     = 2049
  ip_protocol = "tcp"

  description = "Allow NFS access from PharmaFlow EKS"
}
