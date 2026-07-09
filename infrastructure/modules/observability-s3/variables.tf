variable "cluster_name" {
  description = "EKS cluster name — used as bucket name prefix"
  type        = string
}

variable "env" {
  description = "Environment (dev / staging / prod)"
  type        = string
}