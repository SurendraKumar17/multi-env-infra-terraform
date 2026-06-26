# infrastructure/global/

Resources here are shared across dev, staging, and prod — they exist
exactly once per AWS account, not once per environment.

## What's in here
| File | Creates |
|---|---|
| `state-backend.tf` | S3 bucket + DynamoDB table for everyone else's remote state |
| `ecr.tf` | ECR repos, one per service, shared by all envs |
| `dns-tls.tf` | Route53 zone + ACM cert (apply-gated until you set `root_domain`) |
| `github-oidc.tf` | GitHub Actions OIDC provider + the deploy role currently hardcoded by ARN in every env's `main.tf` |

## Why this folder uses LOCAL state, not remote
Every other module's `backend.tf` points at the S3 bucket created in
`state-backend.tf`. This folder can't point at a bucket it's
responsible for creating — that's a circular dependency. So this is
the one place in the whole repo that intentionally uses local state.

**Back up `terraform.tfstate` after every apply in this folder.**
It's the only record of these resources' identity. Losing it doesn't
delete the real AWS resources, but Terraform forgets it manages them
— recoverable via `terraform import`, but avoid needing to.

## You chose to create everything fresh, not import existing resources
This means:
- The hand-created `surendra-terraform-state` S3 bucket and
  `terraform-lock` DynamoDB table need to be **deleted first** (or
  renamed via `var.state_bucket_name`/`var.lock_table_name` if you'd
  rather keep the old ones around untouched and just use new names).
  Otherwise `apply` fails with "already exists" errors.
- ⚠️ **The old bucket currently holds your real dev/staging/prod
  state files** (per `envs/*/backend.tf`, which still point at
  `surendra-terraform-state`). Deleting that bucket destroys those
  state files. Before deleting it: either confirm those environments
  have nothing real running yet, or download copies of
  `dev/terraform.tfstate`, `staging/terraform.tfstate`,
  `prod/terraform.tfstate` first (`aws s3 cp s3://surendra-terraform-state/dev/terraform.tfstate ./backup-dev.tfstate`, etc.)
  so you have a record of what existed, even if you don't plan to
  reuse them.
- The existing hand-created ECR repos need deleting first too, for
  the same "already exists" reason — but note any images currently
  in them will be gone. Re-push from CI after this applies.

## Apply sequence
\```bash
cd infrastructure/global

# 1. Fill in required variables (no defaults for these):
#    github_org, github_repo — create a terraform.tfvars or pass -var
cat > terraform.tfvars <<EOF
github_org  = "SurendraKumar17"
github_repo = "multi-env-infra-terraform"
ecr_repository_names = ["booking-api", "booking-worker"]  # ← your real service names
EOF

# 2. Init with LOCAL backend (default — no -backend-config needed)
terraform init

# 3. Plan and review carefully — this creates real, permanent
#    identifiers (bucket names, OIDC provider) that are annoying to
#    rename later
terraform plan

# 4. Apply
terraform apply

# 5. Note the outputs — you'll need deploy_role_arn next
terraform output deploy_role_arn
\```

## After applying global/, update the three envs
1. In each `envs/<name>/main.tf`, replace the hardcoded
   `arn:aws:iam::<account>:role/github-actions-ecr-role` string in
   both `aws_eks_access_entry.github_actions` and
   `aws_eks_access_policy_association.github_actions` with a
   reference to global's output — easiest done by passing it in as
   a variable (`var.github_deploy_role_arn`) set in each env's
   `terraform.tfvars` from `terraform output -raw deploy_role_arn`
   in `global/`. Cross-module remote-state data sources are an
   alternative if you'd rather not copy the value into tfvars.
2. Once `root_domain` is set and DNS/ACM applies cleanly, update
   `modules/helm`'s ArgoCD ingress values to use the wildcard cert
   ARN and a real subdomain instead of the current bare `http://`
   ALB hostname.
3. Re-run `terraform init` in `envs/dev`, `envs/staging`, `envs/prod`
   — their `backend.tf` files don't need to change (same bucket/table
   names by default), but init needs to re-confirm the backend exists
   now that it's freshly created rather than hand-made.