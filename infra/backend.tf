terraform {
  backend "s3" {
    bucket  = "crypto-pipeline-tfstate-768132174945"
    key     = "crypto-pipeline/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}
