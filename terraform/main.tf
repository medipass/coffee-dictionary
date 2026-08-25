terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Zip dist/ + node_modules/ for Lambda — run `pnpm run build` before `terraform apply`
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
  runtime          = "nodejs18.x"
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
  target        = aws_lambda_function.app.invoke_arn
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.app.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.app.execution_arn}/*/*"
}
