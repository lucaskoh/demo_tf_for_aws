terraform {
  # Partial configuration: scripts/tf.sh passes bucket, region and key with
  # -backend-config, taken from common.state_bucket / common.region of
  # envs/<environment>/values.yaml. Key: aws-multi-vpc/<environment>/compute/terraform.tfstate
  backend "s3" {
    encrypt = true

    # S3 native locking (Terraform >= 1.10), no DynamoDB needed
    use_lockfile = true
  }
}
