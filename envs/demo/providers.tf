provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}

# Authenticates with a short-lived token from `aws eks get-token`
# (the AWS CLI must be available where Terraform runs).
#
# First deployment: the cluster does not exist yet, so run
#   terraform apply -target=module.eks
# once, then run a normal `terraform apply`.
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
  }
}
