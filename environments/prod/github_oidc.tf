# ---------------------------------------------------------
# GitHub Actions OIDC Provider
# ---------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  tags = {
    Name        = "pharmaflow-github-oidc"
    Project     = "PharmaFlow"
    Environment = "prod"
    ManagedBy   = "Terraform"
  }
}

# ---------------------------------------------------------
# GitHub Actions Infrastructure CD Role
# ---------------------------------------------------------

resource "aws_iam_role" "github_infra_cd" {
  name = "pharmaflow-github-infra-cd-role"

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

            "token.actions.githubusercontent.com:sub" = "repo:Highbuilder08@80293873800/PharmaFlow-Infrastructure@1337933940:environment:production"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "pharmaflow-github-infra-cd-role"
    Project     = "PharmaFlow"
    Environment = "prod"
    ManagedBy   = "Terraform"
  }
}

