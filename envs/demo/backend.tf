terraform {
  backend "s3" {
    # state_bucket_name output from bootstrap (backend blocks cannot use variables)
    bucket = "REPLACE_WITH_STATE_BUCKET_NAME"
    key    = "aws-multi-vpc/demo/terraform.tfstate"
    region = "ap-northeast-1"

    encrypt = true

    # S3 native locking (Terraform >= 1.10), no DynamoDB needed
    use_lockfile = true
  }
}
