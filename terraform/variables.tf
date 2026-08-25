variable "aws_region" {
  default = "ap-southeast-2"
}

variable "function_name" {
  default = "coffee-dictionary"
}

variable "cors_host" {
  description = "Allowed CORS origin — leave empty to disable CORS"
  default     = ""
}
