# The cluster lives in the compute layer, so its endpoint and CA come from that
# layer's remote state. Authenticates with a short-lived token from
# `aws eks get-token` (the AWS CLI must be available where Terraform runs).
provider "kubernetes" {
  host                   = local.compute.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(local.compute.eks_cluster_ca)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.compute.eks_cluster_name, "--region", local.region]
  }
}
