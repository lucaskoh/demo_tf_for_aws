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
  description = "Nginx container image"
  type        = string
  default     = "nginx:1.27-alpine"
}

variable "image_url" {
  description = "Public URL of the image shown on the page (S3 object URL)"
  type        = string
}

variable "path_prefix" {
  description = "Path (without slashes) under which the page is served, e.g. html1 -> /html1/index.html"
  type        = string
  default     = "html1"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.path_prefix))
    error_message = "path_prefix must contain only letters, digits, dots, underscores and hyphens (no slashes)."
  }
}

variable "page_title" {
  description = "HTML title of the page"
  type        = string
  default     = "EKS"
}

variable "page_heading" {
  description = "Heading shown on the page"
  type        = string
  default     = "Hello from EKS (VPC-A)"
}

variable "image_alt" {
  description = "Alt text of the image on the page"
  type        = string
  default     = "EKS logo"
}

variable "replicas" {
  description = "Number of pod replicas"
  type        = number
  default     = 1
}

variable "service_port" {
  description = "Port of the Kubernetes Service (the container itself listens on 80, the default of the Nginx image)"
  type        = number
  default     = 80
}

variable "resources" {
  description = "CPU and memory requests/limits of the Nginx container"
  type = object({
    cpu_request    = optional(string, "50m")
    memory_request = optional(string, "32Mi")
    memory_limit   = optional(string, "128Mi")
  })
  default = {}
}

variable "node_port" {
  description = "NodePort exposed on every worker node (the ALB target port)"
  type        = number
  default     = 30080
}
