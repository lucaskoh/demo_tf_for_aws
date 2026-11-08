variable "name" {
  description = "Name of the Deployment, Service and ConfigMap"
  type        = string
}

variable "namespace" {
  description = "Namespace to deploy into"
  type        = string
  default     = "default"
}

variable "image" {
  description = "Container image, for example nginx:1.27-alpine"
  type        = string
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 80

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "container_port must be between 1 and 65535."
  }
}

variable "service_port" {
  description = "Port of the Kubernetes Service"
  type        = number
  default     = 80
}

variable "node_port" {
  description = "NodePort exposed on every worker node (the ALB target port). null = the Service is a ClusterIP, reachable inside the cluster only."
  type        = number
  default     = null

  validation {
    condition     = var.node_port == null || (var.node_port >= 30000 && var.node_port <= 32767)
    error_message = "node_port must be null or between 30000 and 32767."
  }
}

variable "replicas" {
  description = "Number of pod replicas"
  type        = number
  default     = 1
}

variable "health_check_path" {
  description = "HTTP path of the readiness probe"
  type        = string
  default     = "/"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must start with /."
  }
}

variable "resources" {
  description = "CPU and memory requests/limits of the container"
  type = object({
    cpu_request    = optional(string, "50m")
    memory_request = optional(string, "32Mi")
    memory_limit   = optional(string, "128Mi")
  })
  default = {}
}

variable "static_file" {
  description = "Optional file mounted into the container from a ConfigMap (for example the demo page). The same content is mounted at every path in mount_paths (full paths of the file inside the container). null = run the image as it is."
  type = object({
    mount_paths = list(string)
    content     = string
  })
  default = null
}
