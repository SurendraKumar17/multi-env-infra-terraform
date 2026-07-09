locals {
  tags = {
    Environment = var.env
    Project     = var.project
    ManagedBy   = "terraform"
    Cluster     = var.cluster_name
  }
}

# ─────────────────────────────────────────
# DATA
# ─────────────────────────────────────────
data "aws_caller_identity" "current" {}

# ─────────────────────────────────────────
# VPC
# ────────────────────────────────────────
module "vpc" {
  source       = "../../modules/vpc"
  region       = var.region
  cidr         = "10.0.0.0/16"
  azs          = var.azs
  env          = var.env
  project      = var.project
  cluster_name = var.cluster_name
  single_nat_gateway = true
}

# ─────────────────────────────────────────
# EKS
# ─────────────────────────────────────────
module "eks" {
  source       = "../../modules/eks"
  depends_on   = [module.vpc]
  env          = var.env
  project      = var.project
  cluster_name = var.cluster_name
  vpc_id       = module.vpc.vpc_id
  subnet_ids   = module.vpc.private_subnets
  region       = var.region
  max_size     = var.max_size
  desired_size = var.desired_size
  min_size     = var.min_size
}

# ─────────────────────────────────────────
# RDS
# ─────────────────────────────────────────
module "rds" {
  source     = "../../modules/rds"
  depends_on = [module.vpc]

  env        = var.env
  project    = var.project
  vpc_id     = module.vpc.vpc_id
  vpc_cidr   = module.vpc.vpc_cidr
  subnet_ids = module.vpc.private_subnets
}

# ─────────────────────────────────────────
# IAM
# ─────────────────────────────────────────
module "iam" {
  source            = "../../modules/iam"
  depends_on        = [module.eks]
  env               = var.env
  project           = var.project
  cluster_name      = module.eks.cluster_name
  oidc_provider_url = module.eks.oidc_provider_url
  oidc_provider_arn = module.eks.oidc_provider_arn
  alb_policy_json   = file("../../modules/iam/alb-policy.json")
  node_role_name    = module.eks.node_role_name
}

# ─────────────────────────────────────────
# EKS Access Entry for GitHub Actions
# ─────────────────────────────────────────
resource "aws_eks_access_entry" "github_actions" {
  cluster_name  = module.eks.cluster_name
  principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/github-actions-ecr-role"
  type          = "STANDARD"
  depends_on    = [module.eks]
}

resource "aws_eks_access_policy_association" "github_actions" {
  cluster_name  = module.eks.cluster_name
  principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/github-actions-ecr-role"
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  depends_on    = [module.eks]

  access_scope {
    type = "cluster"
  }
}

# ─────────────────────────────────────────
# HELM
# ─────────────────────────────────────────
module "helm" {
  source     = "../../modules/helm"
  depends_on = [module.eks, module.iam]

  cluster_name                = module.eks.cluster_name
  region                      = var.region
  vpc_id                      = module.vpc.vpc_id
  alb_controller_role_arn     = module.iam.alb_controller_role_arn
  ebs_csi_role_arn            = module.iam.ebs_csi_role_arn
  cluster_autoscaler_role_arn = module.iam.cluster_autoscaler_role_arn
  external_secrets_role_arn   = module.iam.external_secrets_role_arn
  env                         = var.env

  alb_controller_replica_count = 1
  argocd_server_replicas       = 1
  argocd_repo_server_replicas  = 1
}

# ─────────────────────────────────────────
# S3 — Observability backends
# ─────────────────────────────────────────
module "observability_s3" {
  source       = "../../modules/observability-s3"
  cluster_name = var.cluster_name
  env          = var.env
}

# ─────────────────────────────────────────
# OUTPUTS
# ─────────────────────────────────────────
output "cluster_name"            { value = module.eks.cluster_name }
output "cluster_endpoint"        { value = module.eks.cluster_endpoint }
output "region"                  { value = var.region }
output "vpc_id"                  { value = module.vpc.vpc_id }
output "alb_controller_role_arn" { value = module.iam.alb_controller_role_arn }
output "argocd_role_arn"         { value = module.iam.argocd_role_arn }
output "observability_role_arn"  { value = module.iam.observability_role_arn }
output "rds_endpoint"            { value = module.rds.db_host }
output "rds_secret_arn"          { value = module.rds.secret_arn }

output "argocd_url" {
  description = "ArgoCD ALB URL — available ~2 mins after apply"
  value       = "http://${module.helm.argocd_hostname}"
}