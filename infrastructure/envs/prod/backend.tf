terraform {
  backend "s3" {
    bucket         = "surendra-terraform-state1"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-lock"
    encrypt        = true
  }
}