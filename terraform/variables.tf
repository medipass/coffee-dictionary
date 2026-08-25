variable "aws_region" {
  default = "us-east-1"
}

variable "function_name" {
  default = "coffee-dictionary"
}

variable "cors_host" {
  description = "Allowed CORS origin — leave empty to disable CORS"
  default     = ""
}
