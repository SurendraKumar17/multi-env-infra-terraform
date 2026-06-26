# =============================================================
# infrastructure/global/state-backend.tf
#
# Creates the S3 bucket + DynamoDB table that envs/dev, envs/staging,
# and envs/prod all point at via their own backend.tf files.
#
# THIS MODULE ITSELF CANNOT USE A REMOTE BACKEND — that's the
# chicken-and-egg problem. Run this with LOCAL state only, then
# never touch it again except for rare changes (e.g. enabling a
# new feature on the bucket). See README.md in this folder for the
# exact apply sequence.
#
# NOTE: bucket names must be globally unique across all of AWS.
# "surendra-terraform-state" matches the name already referenced
# in envs/*/backend.tf — keeping it the same so those files don't
# need to change. If this exact name is taken by someone else,
# you'll get a BucketAlreadyExists error and need to pick a new
# name AND update it in all three envs/*/backend.tf files.
# =============================================================

locals {
  tags = {
    Project   = "microservices"
    ManagedBy = "terraform"
    Scope     = "global"
  }
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = var.state_bucket_name

  tags = merge(local.tags, { Name = var.state_bucket_name })
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled" # protects against accidental state overwrite/corruption
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle rule: keep noncurrent state versions for 90 days, then
# expire — versioning protects against accidental corruption without
# the bucket growing forever from every single apply's state snapshot.
resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"
    filter {}  

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

resource "aws_dynamodb_table" "terraform_lock" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST" # no capacity planning needed for a lock table
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = merge(local.tags, { Name = var.lock_table_name })
}