terraform {
  backend "s3" {
    bucket         = "replace-with-prod-terraform-state-bucket"
    key            = "online-boutique/prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "replace-with-terraform-lock-table"
    encrypt        = true
  }
}
