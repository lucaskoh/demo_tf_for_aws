output "workloads" {
  description = "Deployments on the EKS cluster, resolved (defaults, derived NodePort)."
  value       = local.workloads
}

output "instances" {
  description = "EC2 instances in VPC-B, resolved."
  value       = local.instances
}

output "backends" {
  description = "Routes: a path on the ALB that leads to one workload or one instance."
  value       = local.backends
}

output "exposed_workloads" {
  description = "The workloads that at least one backend routes to (they get a NodePort)."
  value       = local.exposed_workloads
}

output "routed_instances" {
  description = "The instances that at least one backend routes to."
  value       = local.routed_instances
}

output "problems" {
  description = "Every rule that failed, as a full message. Empty when the environment is valid."
  value       = local.problems
}
