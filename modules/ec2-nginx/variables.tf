variable "name" {
  description = "Name tag of the instance"
  type        = string
  default     = "vpc-b-nginx"
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

variable "tags" {
  description = "Extra tags applied to every resource"
  type        = map(string)
  default     = {}
}
