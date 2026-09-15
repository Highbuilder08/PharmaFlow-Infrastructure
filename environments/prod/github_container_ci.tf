# ---------------------------------------------------------
# GitHub Actions Container CI Role
#
# 목적:
# - Highbuilder08/PharmaFlow 애플리케이션 저장소의
#   GitHub Actions가 OIDC를 통해 AWS에 인증
# - 장기 AWS Access Key를 GitHub Secrets에 저장하지 않음
# - PharmaFlow Django / Nginx ECR Repository에만
#   컨테이너 이미지를 Push
# ---------------------------------------------------------

resource "aws_iam_role" "github_container_ci" {
  name = "pharmaflow-github-container-ci-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }

        Action = "sts:AssumeRoleWithWebIdentity"

        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"

            # production Environment를 사용하는
            # PharmaFlow 애플리케이션 저장소의 Workflow만 허용
            "token.actions.githubusercontent.com:sub" = "repo:Highbuilder08/PharmaFlow:environment:production"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "pharmaflow-github-container-ci-role"
    Project     = "PharmaFlow"
    Environment = "prod"
    ManagedBy   = "Terraform"
  }
}


# ---------------------------------------------------------
# GitHub Actions Container CI Policy
# ---------------------------------------------------------

resource "aws_iam_role_policy" "github_container_ci" {
  name = "pharmaflow-github-container-ci-policy"
  role = aws_iam_role.github_container_ci.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [

      # ---------------------------------------------------
      # ECR Login
      #
      # GetAuthorizationToken은 특정 Repository ARN으로
      # 제한할 수 없으므로 Resource = "*"
      # ---------------------------------------------------
      {
        Sid    = "ECRAuthorization"
        Effect = "Allow"

        Action = [
          "ecr:GetAuthorizationToken"
        ]

        Resource = "*"
      },

      # ---------------------------------------------------
      # PharmaFlow Container Image Push
      #
      # Django / Nginx 두 Repository에만 허용
      # ---------------------------------------------------
      {
        Sid    = "ECRImagePush"
        Effect = "Allow"

        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]

        Resource = [
          aws_ecr_repository.django.arn,
          aws_ecr_repository.nginx.arn
        ]
      }
    ]
  })
}


# ---------------------------------------------------------
# Output
# ---------------------------------------------------------

output "github_container_ci_role_arn" {
  description = "IAM Role ARN used by PharmaFlow container CI via GitHub Actions OIDC"
  value       = aws_iam_role.github_container_ci.arn
}
