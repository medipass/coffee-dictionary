# Lets GitHub Actions assume an AWS role via OIDC — no long-lived AWS keys
# stored in GitHub. Scoped to pull_request runs on this repo only.

variable "github_repo" {
  description = "GitHub repo in \"owner/name\" form allowed to assume the deploy role"
  default     = "mdraj2/coffee-dictionary"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

resource "aws_iam_role" "github_actions" {
  name = "${var.function_name}-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:pull_request"
        }
      }
    }]
  })
}

# Scoped to exactly what `tofu apply` needs for this project's resources —
# not admin access. apigatewayv2 and cloudfront don't support fine-grained
# resource ARNs at creation time, so those two are action-scoped instead.
resource "aws_iam_role_policy" "github_actions" {
  name = "${var.function_name}-deploy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LambdaFunction"
        Effect = "Allow"
        Action = [
          "lambda:GetFunction",
          "lambda:CreateFunction",
          "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration",
          "lambda:DeleteFunction",
          "lambda:GetPolicy",
          "lambda:AddPermission",
          "lambda:RemovePermission",
          "lambda:TagResource",
          "lambda:UntagResource",
          "lambda:ListVersionsByFunction",
          "lambda:ListTags",
        ]
        Resource = "arn:aws:lambda:${var.aws_region}:*:function:${var.function_name}"
      },
      {
        Sid    = "LambdaExecutionRole"
        Effect = "Allow"
        Action = [
          "iam:GetRole",
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:TagRole",
          "iam:PassRole",
          "iam:PutRolePolicy",
          "iam:GetRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:ListRolePolicies",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:ListAttachedRolePolicies",
        ]
        Resource = "arn:aws:iam::*:role/${var.function_name}-role"
      },
      {
        Sid      = "ApiGateway"
        Effect   = "Allow"
        Action   = ["apigateway:GET", "apigateway:POST", "apigateway:PUT", "apigateway:PATCH", "apigateway:DELETE"]
        Resource = "arn:aws:apigateway:${var.aws_region}::/apis*"
      },
      {
        Sid    = "CloudFront"
        Effect = "Allow"
        Action = [
          "cloudfront:GetDistribution",
          "cloudfront:CreateDistribution",
          "cloudfront:UpdateDistribution",
          "cloudfront:DeleteDistribution",
          "cloudfront:TagResource",
          "cloudfront:ListTagsForResource",
        ]
        Resource = "*"
      },
      {
        Sid      = "TerraformState"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "arn:aws:s3:::coffee-dictionary-tfstate-699799608914/coffee-dictionary/*"
      },
      {
        Sid      = "TerraformStateBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = "arn:aws:s3:::coffee-dictionary-tfstate-699799608914"
      },
    ]
  })
}

output "github_actions_role_arn" {
  description = "Role ARN for the GitHub Actions workflow to assume via OIDC"
  value       = aws_iam_role.github_actions.arn
}
