terraform {
  backend "s3" {
    bucket         = "replace-with-dev-terraform-state-bucket"
    key            = "online-boutique/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "replace-with-terraform-lock-table"
    encrypt        = true
  }
}
