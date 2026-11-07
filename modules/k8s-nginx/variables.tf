variable "name" {
  description = "Name of the Deployment, Service and ConfigMap"
  type        = string
  default     = "nginx-html1"
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

variable "node_port" {
  description = "NodePort exposed on every worker node (the ALB target port)"
  type        = number
  default     = 30080
}
