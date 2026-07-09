variable "region"      {}
variable "cidr"        {}
variable "env"         {}
variable "azs" {
  type = list(string)
}
variable "project" {
  default = "microservices"
}

variable "cluster_name" {
  type = string
}

variable "single_nat_gateway" {
  description = "If true, creates ONE NAT Gateway shared by all AZs (cheaper for dev). If false, one NAT per AZ (HA for prod)."
  type        = bool
  default     = false
}