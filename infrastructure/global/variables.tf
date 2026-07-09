variable "region" {
  description = "AWS region for all global resources"
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "S3 bucket name for Terraform remote state — must be globally unique across AWS"
  type        = string
  default     = "surendra-terraform-state"
}

variable "lock_table_name" {
  description = "DynamoDB table name for Terraform state locking"
  type        = string
  default     = "terraform-lock"
}

variable "ecr_repository_names" {
  description = "List of service names to create ECR repositories for"
  type        = list(string)
  default     = [] # set this to your real service list, e.g. ["frontend", "auth-service", "search-service", "booking-service", "payment-service", "notification-service"]
}

variable "root_domain" {
  description = "Root domain for Route53 + ACM, e.g. \"example.com\". Leave empty until a real domain is registered — see dns-tls.tf."
  type        = string
  default     = ""
}