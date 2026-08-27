# ---------------------------------------------------------
# GitHub Actions Infrastructure CD Policy
#
# 목적:
# - GitHub Actions OIDC Role이 PharmaFlow Terraform을 실행
# - 현재 Terraform이 관리하는 AWS 서비스만 허용
# - IAM 생성/수정/삭제 권한은 부여하지 않음
# - OIDC / IAM 변경은 Server1의 관리자 계정에서 Bootstrap
# ---------------------------------------------------------

resource "aws_iam_role_policy" "github_infra_cd" {
  name = "pharmaflow-github-infra-cd-policy"
  role = aws_iam_role.github_infra_cd.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [

      # ---------------------------------------------------
      # Terraform / AWS Provider 기본 확인
      # ---------------------------------------------------
      {
        Sid    = "STSIdentity"
        Effect = "Allow"

        Action = [
          "sts:GetCallerIdentity"
        ]

        Resource = "*"
      },

      # ---------------------------------------------------
      # Terraform S3 Remote State
      # ---------------------------------------------------
      {
        Sid    = "TerraformStateBucket"
        Effect = "Allow"

        Action = [
          "s3:GetBucketLocation",
          "s3:ListBucket"
        ]

        Resource = "arn:aws:s3:::pharmaflow-terraform-state-962450756907"
      },

      {
        Sid    = "TerraformStateObjects"
        Effect = "Allow"

        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]

        Resource = [
          "arn:aws:s3:::pharmaflow-terraform-state-962450756907/prod/terraform.tfstate",
          "arn:aws:s3:::pharmaflow-terraform-state-962450756907/prod/terraform.tfstate.tflock"
        ]
      },

      # ---------------------------------------------------
      # EC2 / VPC / Security Group / AMI /
      # Launch Template / EIP / Route
      # ---------------------------------------------------
      {
        Sid    = "EC2Infrastructure"
        Effect = "Allow"

        Action = [
          "ec2:*"
        ]

        Resource = "*"
      },

      # ---------------------------------------------------
      # Auto Scaling
      # ---------------------------------------------------
      {
        Sid    = "AutoScaling"
        Effect = "Allow"

        Action = [
          "autoscaling:*"
        ]

        Resource = "*"
      },

      # ---------------------------------------------------
      # ALB / Target Group / Listener
      # ---------------------------------------------------
      {
        Sid    = "ElasticLoadBalancing"
        Effect = "Allow"

        Action = [
          "elasticloadbalancing:*"
        ]

        Resource = "*"
      },

      # ---------------------------------------------------
      # RDS
      # ---------------------------------------------------
      {
        Sid    = "RDS"
        Effect = "Allow"

        Action = [
          "rds:*"
        ]

        Resource = "*"
      },

      # ---------------------------------------------------
      # EFS
      # ---------------------------------------------------
      {
        Sid    = "EFS"
        Effect = "Allow"

        Action = [
          "elasticfilesystem:*"
        ]

        Resource = "*"
      },

      # ---------------------------------------------------
      # Route 53
      # ---------------------------------------------------
      {
        Sid    = "Route53"
        Effect = "Allow"

        Action = [
          "route53:*"
        ]

        Resource = "*"
      },

      # ---------------------------------------------------
      # ACM
      # ---------------------------------------------------
      {
        Sid    = "ACM"
        Effect = "Allow"

        Action = [
          "acm:*"
        ]

        Resource = "*"
      },

      # ---------------------------------------------------
      # AWS WAF v2
      # ---------------------------------------------------
      {
        Sid    = "WAF"
        Effect = "Allow"

        Action = [
          "wafv2:*"
        ]

        Resource = "*"
      },

      # ---------------------------------------------------
      # CloudWatch
      # ---------------------------------------------------
      {
        Sid    = "CloudWatch"
        Effect = "Allow"

        Action = [
          "cloudwatch:*"
        ]

        Resource = "*"
      },

      # ---------------------------------------------------
      # SNS
      # ---------------------------------------------------
      {
        Sid    = "SNS"
        Effect = "Allow"

        Action = [
          "sns:*"
        ]

        Resource = "*"
      },

      # ---------------------------------------------------
      # Amazon SES v2
      # ---------------------------------------------------
      {
        Sid    = "SES"
        Effect = "Allow"

        Action = [
          "ses:*",
          "sesv2:*"
        ]

        Resource = "*"
      },

      # ---------------------------------------------------
      # IAM Bootstrap 리소스 조회 전용
      #
      # GitHub CD Role은 IAM을 수정할 수 없음.
      # 같은 Terraform State의 OIDC/Role refresh만 허용.
      # ---------------------------------------------------
      {
        Sid    = "IAMReadOnly"
        Effect = "Allow"

        Action = [
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:GetOpenIDConnectProvider",
          "iam:ListAttachedRolePolicies",
          "iam:ListRolePolicies",
          "iam:ListPolicyVersions",
          "iam:ListOpenIDConnectProviders"
        ]

        Resource = "*"
      }
    ]
  })
}
