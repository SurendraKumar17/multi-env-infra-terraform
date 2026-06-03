## ============================================================
## modules/observability-s3/main.tf
## Creates 4 S3 buckets for Loki, Tempo, Thanos
## Naming: {cluster_name}-{purpose}
## e.g.  dev-eks-cluster-loki-chunks
## ============================================================

locals {
  buckets = [
    "${var.cluster_name}-loki-chunks",
    "${var.cluster_name}-loki-ruler",
    "${var.cluster_name}-tempo-traces",
    "${var.cluster_name}-thanos-metrics",
  ]

  tags = {
    Environment = var.env
    Project     = "observability"
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket" "observability" {
  for_each = toset(local.buckets)
  bucket   = each.key
  force_destroy = true 
  tags     = merge(local.tags, { Name = each.key })
}

resource "aws_s3_bucket_public_access_block" "observability" {
  for_each = aws_s3_bucket.observability

  bucket                  = each.value.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "observability" {
  for_each = aws_s3_bucket.observability

  bucket = each.value.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "observability" {
  for_each = aws_s3_bucket.observability

  bucket = each.value.id

  rule {
    id     = "expire-old-objects"
    status = "Enabled"

    filter {}  # applies to all objects

    expiration {
      days = lookup({
        "${var.cluster_name}-loki-chunks"    = 31
        "${var.cluster_name}-loki-ruler"     = 90
        "${var.cluster_name}-tempo-traces"   = 14
        "${var.cluster_name}-thanos-metrics" = 90
      }, each.key, 30)
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

## ── outputs ──────────────────────────────────────────────────
output "bucket_names" {
  value = { for k, v in aws_s3_bucket.observability : k => v.bucket }
}

output "bucket_arns" {
  value = { for k, v in aws_s3_bucket.observability : k => v.arn }
}