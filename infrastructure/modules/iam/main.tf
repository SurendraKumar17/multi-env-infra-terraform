locals {
  oidc_id = replace(var.oidc_provider_url, "https://", "")

  tags = {
    Environment = var.env
    Project     = var.project
    ManagedBy   = "terraform"
  }
}

# ────────────────────────────────────────────────
# IRSA — AWS Load Balancer Controller
# ────────────────────────────────────────────────
resource "aws_iam_role" "alb_controller" {
  name = "${var.cluster_name}-alb-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_id}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${local.oidc_id}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
  tags = local.tags
}

resource "aws_iam_policy" "alb_controller" {
  name   = "${var.cluster_name}-alb-controller-policy"
  policy = var.alb_policy_json
  tags   = local.tags
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

resource "aws_iam_role_policy" "alb_extra" {
  name = "${var.cluster_name}-alb-extra"
  role = var.node_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "elasticloadbalancing:*",
        "ec2:Describe*",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:CreateSecurityGroup",
        "ec2:DeleteSecurityGroup",
        "ec2:CreateTags",
        "ec2:DeleteTags",
        "cognito-idp:DescribeUserPoolClient",
        "acm:ListCertificates",
        "acm:DescribeCertificate",
        "iam:ListServerCertificates",
        "iam:GetServerCertificate",
        "waf-regional:*",
        "wafv2:*",
        "shield:*",
        "tag:GetResources"
      ]
      Resource = "*"
    }]
  })
}

# ────────────────────────────────────────────────
# IRSA — ArgoCD
# ────────────────────────────────────────────────
resource "aws_iam_role" "argocd" {
  name = "${var.cluster_name}-argocd"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_id}:sub" = "system:serviceaccount:argocd:argocd-server"
          "${local.oidc_id}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "argocd_ecr" {
  role       = aws_iam_role.argocd.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ────────────────────────────────────────────────
# IRSA — EBS CSI Driver
# ────────────────────────────────────────────────
resource "aws_iam_role" "ebs_csi" {
  name = "${var.cluster_name}-ebs-csi"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_id}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          "${local.oidc_id}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# ────────────────────────────────────────────────
# IRSA — Cluster Autoscaler
# ────────────────────────────────────────────────
resource "aws_iam_role" "cluster_autoscaler" {
  name = "${var.cluster_name}-cluster-autoscaler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_id}:sub" = "system:serviceaccount:kube-system:cluster-autoscaler-aws-cluster-autoscaler"
          "${local.oidc_id}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "cluster_autoscaler" {
  name = "${var.cluster_name}-cluster-autoscaler"
  role = aws_iam_role.cluster_autoscaler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeScalingActivities",
        "autoscaling:DescribeTags",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
        "ec2:DescribeLaunchTemplateVersions",
        "ec2:DescribeInstanceTypes",
        "eks:DescribeNodegroup"
      ]
      Resource = "*"
    }]
  })
}

# ────────────────────────────────────────────────
# IRSA — External Secrets Operator
# ────────────────────────────────────────────────
resource "aws_iam_role" "external_secrets" {
  name = "${var.cluster_name}-external-secrets"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_id}:sub" = "system:serviceaccount:external-secrets:external-secrets"
          "${local.oidc_id}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "external_secrets" {
  name = "${var.cluster_name}-external-secrets"
  role = aws_iam_role.external_secrets.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
      Resource = "*"
    }]
  })
}

# ────────────────────────────────────────────────
# Node role policy attachments
# ────────────────────────────────────────────────
resource "aws_iam_role_policy_attachment" "node_alb" {
  role       = var.node_role_name
  policy_arn = aws_iam_policy.alb_controller.arn
}

resource "aws_iam_role_policy_attachment" "node_ebs" {
  role       = var.node_role_name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# ────────────────────────────────────────────────
# IRSA — Observability (Loki + Tempo + Thanos)
# ────────────────────────────────────────────────
resource "aws_iam_role" "observability" {
  name = "${var.cluster_name}-observability"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_id}:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "${local.oidc_id}:sub" = "system:serviceaccount:observability:*"
        }
      }
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "observability_s3" {
  name = "${var.cluster_name}-observability-s3"
  role = aws_iam_role.observability.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          "arn:aws:s3:::${var.cluster_name}-loki-chunks",
          "arn:aws:s3:::${var.cluster_name}-loki-ruler",
          "arn:aws:s3:::${var.cluster_name}-tempo-traces",
          "arn:aws:s3:::${var.cluster_name}-thanos-metrics"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "arn:aws:s3:::${var.cluster_name}-loki-chunks/*",
          "arn:aws:s3:::${var.cluster_name}-loki-ruler/*",
          "arn:aws:s3:::${var.cluster_name}-tempo-traces/*",
          "arn:aws:s3:::${var.cluster_name}-thanos-metrics/*"
        ]
      }
    ]
  })
}

# ────────────────────────────────────────────────
# GitHub Actions OIDC Provider (one per AWS account)
# ────────────────────────────────────────────────
# NOTE: If a GitHub Actions OIDC provider already exists in this AWS
# account (e.g. created by another Terraform config or manually), remove
# this resource and instead pass its ARN in via a variable / data source
# to avoid a "provider already exists" error on apply.
data "tls_certificate" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github_actions.certificates[0].sha1_fingerprint]
  tags            = local.tags
}

# ────────────────────────────────────────────────
# IAM Role — GitHub Actions (ECR push + EKS access)
# ────────────────────────────────────────────────
resource "aws_iam_role" "github_actions_ecr" {
  name = "github-actions-ecr-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github_actions.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          # TODO: replace ORG/REPO with your actual GitHub org and repo.
          # Narrow further to a specific branch if possible, e.g.:
          # "token.actions.githubusercontent.com:sub" = "repo:ORG/REPO:ref:refs/heads/main"
          "token.actions.githubusercontent.com:sub" = "repo:ORG/REPO:*"
        }
      }
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "github_actions_ecr" {
  role       = aws_iam_role.github_actions_ecr.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

output "github_actions_ecr_role_arn" {
  value = aws_iam_role.github_actions_ecr.arn
}
