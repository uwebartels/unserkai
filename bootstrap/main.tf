provider "aws" {
  profile = var.profile
  region  = var.region
}

resource "aws_s3_bucket" "this" {
  bucket = var.s3_bucket_name
}
data "aws_caller_identity" "current" {}
