terraform {
  backend "s3" {
    bucket         = "replace-with-stage-terraform-state-bucket"
    key            = "online-boutique/stage/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "replace-with-terraform-lock-table"
    encrypt        = true
  }
}
