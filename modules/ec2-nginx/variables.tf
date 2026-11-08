variable "name" {
  description = "Name tag of the instance"
  type        = string
}

variable "subnet_id" {
  description = "Subnet to launch the instance in"
  type        = string
}

variable "private_ip" {
  description = "Fixed private IP (must be inside the subnet CIDR), used as the ALB IP target"
  type        = string
}

variable "security_group_ids" {
  description = "Security groups attached to the instance"
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "image_url" {
  description = "Public URL of the image shown on the page (S3 object URL)"
  type        = string
}

variable "ami_name_pattern" {
  description = "Name pattern of the Amazon AMI to use (the most recent match is picked)"
  type        = string
  default     = "al2023-ami-2023.*-x86_64"
}

variable "associate_public_ip" {
  description = "Give the instance a public IP. Needed to reach the internet (dnf) without a NAT Gateway."
  type        = bool
  default     = true
}

variable "root_volume_size" {
  description = "Size of the root volume in GiB"
  type        = number
  default     = 8
}

variable "root_volume_type" {
  description = "Type of the root volume"
  type        = string
  default     = "gp3"
}

variable "http_port" {
  description = "Port Nginx listens on"
  type        = number
  default     = 80

  validation {
    condition     = var.http_port >= 1 && var.http_port <= 65535
    error_message = "http_port must be between 1 and 65535."
  }
}

variable "path_prefix" {
  description = "Path (without slashes) under which the page is served, e.g. html2 -> /html2/index.html"
  type        = string
  default     = "html2"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.path_prefix))
    error_message = "path_prefix must contain only letters, digits, dots, underscores and hyphens (no slashes)."
  }
}

variable "page_title" {
  description = "HTML title of the page"
  type        = string
  default     = "EC2"
}

variable "page_heading" {
  description = "Heading shown on the page"
  type        = string
  default     = "Hello from EC2 (VPC-B via VPC Peering)"
}

variable "image_alt" {
  description = "Alt text of the image on the page"
  type        = string
  default     = "EC2 logo"
}

variable "tags" {
  description = "Extra tags applied to every resource"
  type        = map(string)
  default     = {}
}
