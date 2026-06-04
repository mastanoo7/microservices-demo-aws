terraform {
  backend "s3" {
    bucket         = "replace-with-qa-terraform-state-bucket"
    key            = "online-boutique/qa/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "replace-with-terraform-lock-table"
    encrypt        = true
  }
}
