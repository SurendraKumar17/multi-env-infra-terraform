terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # INTENTIONALLY NO remote backend block here.
  #
  # This module creates the S3 bucket + DynamoDB table that every
  # OTHER module's remote backend depends on. It cannot depend on
  # itself. State for infrastructure/global lives in a local
  # terraform.tfstate file.
  #
  # Treat that local state file as sensitive and irreplaceable:
  #   - Commit it to a PRIVATE, separate location (e.g. encrypted,
  #     or a restricted-access secrets repo) — NOT to the main repo
  #     in plaintext, since it will contain real ARNs/IDs.
  #   - Or at minimum, back it up somewhere durable after every apply.
  # If this local state is lost, you won't lose the real AWS
  # resources, but Terraform will lose track of them — recoverable
  # via `terraform import` for each resource, but tedious. Back it up.
}

provider "aws" {
  region = var.region
}