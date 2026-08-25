terraform {
  required_version = ">= 1.12.6"
  required_providers {
    aws = {
      source  = "registry.opentofu.org/hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Zip dist/ + node_modules/ for Lambda — run `pnpm run build` before `tofu apply`
data "archive_file" "app" {
  type        = "zip"
  source_dir  = "${path.module}/.."
  output_path = "${path.module}/app.zip"
  excludes = [
    ".git",
    ".github",
    "src",
    "terraform",
    "Dockerfile",
    ".dockerignore",
    ".gitignore",
    "tsconfig.json",
    "pnpm-lock.yaml",
    "CLAUDE.md",
    "README.md",
    "LICENSE",
  ]
}

resource "aws_iam_role" "lambda" {
  name = "${var.function_name}-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "basic_execution" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "app" {
  filename         = data.archive_file.app.output_path
  function_name    = var.function_name
  role             = aws_iam_role.lambda.arn
  handler          = "dist/lambda.handler"
  runtime          = "nodejs22.x"
  source_code_hash = data.archive_file.app.output_base64sha256

  environment {
    variables = {
      CORS_HOST = var.cors_host
    }
  }
}

resource "aws_apigatewayv2_api" "app" {
  name          = var.function_name
  protocol_type = "HTTP"
}

# payload_format_version = "1.0" — aws-serverless-express only understands the
# REST-API-shaped event (event.path / event.httpMethod), not HTTP API's 2.0 event.
resource "aws_apigatewayv2_integration" "app" {
  api_id                 = aws_apigatewayv2_api.app.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.app.invoke_arn
  payload_format_version = "1.0"
}

resource "aws_apigatewayv2_route" "app" {
  api_id    = aws_apigatewayv2_api.app.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.app.id}"
}

resource "aws_apigatewayv2_stage" "app" {
  api_id      = aws_apigatewayv2_api.app.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.app.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.app.execution_arn}/*/*"
}

# HTTP APIs (apigatewayv2) can't attach WAF or a resource policy, so geo-restriction
# happens at a CloudFront distribution in front of the API instead.
resource "aws_cloudfront_distribution" "app" {
  enabled = true
  comment = "${var.function_name} — geo-restricted to Australia"

  origin {
    domain_name = trimprefix(aws_apigatewayv2_api.app.api_endpoint, "https://")
    origin_id   = "apigw"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "apigw"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]

    # Managed policies: CachingDisabled + AllViewerExceptHostHeader — pass every
    # request straight through to the API, letting CloudFront set the Host header.
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
  }

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["AU"]
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
