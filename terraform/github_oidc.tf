# Lets GitHub Actions assume AWS roles via OIDC — no long-lived AWS keys
# stored in GitHub. Two separate roles, deliberately not one:
#
#   - github_actions_plan: assumable only from `pull_request` runs, read-only.
#     `pull_request` (not `pull_request_target`) executes the workflow file AS
#     COMMITTED IN THE PR, so a PR could edit the workflow to run `apply`
#     instead of `plan` — this role's policy can't do anything destructive
#     even if it did.
#   - github_actions: assumable only from a `push` to `refs/heads/main`
#     (i.e. after merge), full read/write for `tofu apply`.
# GitHub's OIDC `sub` claim identifies the repo by immutable owner/repo
# database IDs, not by name — e.g. "repo:mdraj2@46102339/coffee-dictionary@1345664037:...",
# not "repo:mdraj2/coffee-dictionary:...". Confirmed via CloudTrail against a
# live AssumeRoleWithWebIdentity AccessDenied event; the plain name form
# silently never matches.
variable "github_repo" {
  description = "GitHub repo as it appears in the OIDC sub claim: \"owner@ownerId/name@repoId\""
  default     = "mdraj2@46102339/coffee-dictionary@1345664037"
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
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:ref:refs/heads/main"
        }
      }
    }]
  })
}

resource "aws_iam_role" "github_actions_plan" {
  name = "${var.function_name}-github-actions-plan"

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

# Read-only mirror of aws_iam_role_policy.github_actions below, for PR plans.
resource "aws_iam_role_policy" "github_actions_plan" {
  name = "${var.function_name}-plan"
  role = aws_iam_role.github_actions_plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "LambdaFunction"
        Effect   = "Allow"
        Action   = ["lambda:GetFunction", "lambda:GetFunctionCodeSigningConfig", "lambda:GetPolicy", "lambda:ListVersionsByFunction", "lambda:ListTags"]
        Resource = "arn:aws:lambda:${var.aws_region}:*:function:${var.function_name}"
      },
      {
        Sid      = "LambdaExecutionRole"
        Effect   = "Allow"
        Action   = ["iam:GetRole", "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies"]
        Resource = "arn:aws:iam::*:role/${var.function_name}-role"
      },
      {
        # Both roles are themselves in state (aws_iam_openid_connect_provider.github,
        # aws_iam_role.github_actions*), so every plan/apply refreshes them too.
        Sid    = "OidcSelfRead"
        Effect = "Allow"
        Action = ["iam:GetOpenIDConnectProvider", "iam:GetRole", "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies"]
        Resource = [
          aws_iam_openid_connect_provider.github.arn,
          "arn:aws:iam::*:role/${var.function_name}-github-actions",
          "arn:aws:iam::*:role/${var.function_name}-github-actions-plan",
        ]
      },
      {
        Sid      = "ApiGateway"
        Effect   = "Allow"
        Action   = ["apigateway:GET"]
        Resource = "arn:aws:apigateway:${var.aws_region}::/apis*"
      },
      {
        Sid      = "CloudFront"
        Effect   = "Allow"
        Action   = ["cloudfront:GetDistribution", "cloudfront:ListTagsForResource"]
        Resource = "*"
      },
      {
        Sid      = "TerraformStateRead"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "arn:aws:s3:::coffee-dictionary-tfstate-699799608914/coffee-dictionary/terraform.tfstate"
      },
      {
        Sid      = "TerraformStateLock"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "arn:aws:s3:::coffee-dictionary-tfstate-699799608914/coffee-dictionary/terraform.tfstate.tflock"
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
          "lambda:GetFunctionCodeSigningConfig",
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
        Sid    = "OidcSelfRead"
        Effect = "Allow"
        Action = ["iam:GetOpenIDConnectProvider", "iam:GetRole", "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies"]
        Resource = [
          aws_iam_openid_connect_provider.github.arn,
          "arn:aws:iam::*:role/${var.function_name}-github-actions",
          "arn:aws:iam::*:role/${var.function_name}-github-actions-plan",
        ]
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
  description = "Role ARN the apply workflow (push to main) assumes via OIDC"
  value       = aws_iam_role.github_actions.arn
}

output "github_actions_plan_role_arn" {
  description = "Role ARN the plan workflow (pull_request) assumes via OIDC"
  value       = aws_iam_role.github_actions_plan.arn
}
