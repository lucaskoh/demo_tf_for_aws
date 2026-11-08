variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version. null = the EKS default for new clusters. Pin a version that is in standard support, because extended support costs much more per hour."
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "Subnets (at least 2 AZs) for the control plane ENIs and the node group"
  type        = list(string)
}

variable "node_sg_id" {
  description = "Extra security group for worker nodes (eks-node-sg), attached together with the cluster security group"
  type        = string
}

variable "instance_types" {
  description = "Instance types for the node group. Several types improve Spot availability."
  type        = list(string)
  default     = ["t3.small", "t3a.small"]
}

variable "capacity_type" {
  description = "SPOT or ON_DEMAND"
  type        = string
  default     = "SPOT"

  validation {
    condition     = contains(["SPOT", "ON_DEMAND"], var.capacity_type)
    error_message = "capacity_type must be SPOT or ON_DEMAND."
  }
}

variable "desired_size" {
  description = "Desired number of nodes"
  type        = number
  default     = 1
}

variable "min_size" {
  description = "Minimum number of nodes"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of nodes"
  type        = number
  default     = 2
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public Kubernetes API endpoint (CI runners need public access)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "admin_principal_arns" {
  description = "IAM principals (users or roles) with cluster-admin access. Must include whoever runs Terraform, because the creator is NOT granted admin automatically."
  type        = list(string)

  validation {
    condition     = length(var.admin_principal_arns) > 0
    error_message = "Provide at least one admin principal, otherwise nobody can manage the cluster."
  }
}

variable "view_principal_arns" {
  description = "IAM principals with read-only cluster access (e.g. the CI plan role)"
  type        = list(string)
  default     = []
}

variable "ami_type" {
  description = "AMI type of the node group"
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "node_group_name_suffix" {
  description = "Suffix of the node group name (<cluster_name>-<suffix>)"
  type        = string
  default     = "nodes"
}

variable "max_unavailable_nodes" {
  description = "Maximum number of nodes that may be unavailable during a node group update"
  type        = number
  default     = 1
}

variable "endpoint_public_access" {
  description = "Enable the public Kubernetes API endpoint"
  type        = bool
  default     = true
}

variable "endpoint_private_access" {
  description = "Enable the private Kubernetes API endpoint (inside the VPC)"
  type        = bool
  default     = false
}

variable "imds_hop_limit" {
  description = "IMDSv2 hop limit of the nodes. 2 lets pods reach the metadata service."
  type        = number
  default     = 2
}

variable "tags" {
  description = "Extra tags applied to every resource"
  type        = map(string)
  default     = {}
}
