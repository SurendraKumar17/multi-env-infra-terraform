# =============================================================
# infrastructure/global/ecr.tf
#
# One ECR repo per service, shared across all environments —
# images are tagged per-env/per-build (e.g. booking-api:dev-abc123,
# booking-api:prod-v1.4.0) rather than having separate repos per env.
# This is the standard pattern: a separate repo per environment just
# means duplicate image storage and more IAM surface for no benefit,
# since tags already provide the separation you need.
#
# You mentioned these repos already exist, created by hand. Since
# you've chosen to create everything fresh rather than import, the
# OLD hand-made repos will need to be deleted manually in the AWS
# console/CLI first, or this apply will fail with
# "RepositoryAlreadyExistsException" for each name below.
#
# Update var.ecr_repository_names to match your actual service list.
# =============================================================

resource "aws_ecr_repository" "service" {
  for_each = toset(var.ecr_repository_names)

  name                 = each.value
  image_tag_mutability = "IMMUTABLE" # prevents accidentally overwriting a tag like "latest" or "v1.0.0"

  image_scanning_configuration {
    scan_on_push = true # continuous vulnerability scanning, built in rather than bolted on later
  }

  tags = merge(local.tags, { Name = each.value })
}

# Lifecycle policy: keep the last 20 images per repo, expire older
# ones. Without this, ECR storage cost grows unbounded as CI pushes
# a new image on every commit.
resource "aws_ecr_lifecycle_policy" "service" {
  for_each   = aws_ecr_repository.service
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 20 images, expire the rest"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = { type = "expire" }
    }]
  })
}

output "ecr_repository_urls" {
  description = "Map of service name => full ECR repository URL, for use in CI/CD push steps and envs/* Helm values"
  value       = { for k, v in aws_ecr_repository.service : k => v.repository_url }
}