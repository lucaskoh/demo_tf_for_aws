output "service_name" {
  description = "Name of the NodePort Service"
  value       = kubernetes_service_v1.app.metadata[0].name
}

output "node_port" {
  description = "NodePort exposed on the worker nodes"
  value       = var.node_port
}
