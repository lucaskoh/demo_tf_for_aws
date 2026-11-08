terraform {
  backend "s3" {
    # state_bucket_name output from bootstrap. Backend blocks cannot use variables or read
    # values.yaml, so keep bucket and region in sync with common.state_bucket and
    # common.region in envs/demo/values.yaml.
    bucket = "lucaskoh-tfstate-demo-22f4d2"
    key    = "aws-multi-vpc/demo/compute/terraform.tfstate"
    region = "ap-northeast-1"

    encrypt = true

    # S3 native locking (Terraform >= 1.10), no DynamoDB needed
    use_lockfile = true
  }
}
