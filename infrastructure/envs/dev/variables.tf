variable "region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  default     = "dev-eks-cluster"
}

variable "azs" {
  description = "Availability zones"
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "env" {
  description = "Environment name"
  default     = "dev"
}

variable "project" {
  description = "Project name"
  default     = "microservices"
}

variable "max_size" {
  description = "Max number of nodes"
  default     = 6
}

variable "desired_size" {
  description = "Desired number of nodes"
  default     = 3
}

variable "min_size" {
  description = "Min number of nodes"
  default     = 2
}