output "api_url" {
  description = "Direct API Gateway URL — not geo-restricted, exists only as the CloudFront origin"
  value       = aws_apigatewayv2_api.app.api_endpoint
}

output "cloudfront_url" {
  description = "Public URL — geo-restricted to Australia via CloudFront"
  value       = "https://${aws_cloudfront_distribution.app.domain_name}"
}
