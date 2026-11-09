variable "name" {
  description = "Name tag of the instance"
  type        = string
}

variable "subnet_id" {
  description = "Subnet to launch the instance in"
  type        = string
}

variable "private_ip" {
  description = "Fixed private IP inside the subnet CIDR. null = AWS picks a free address of the subnet (it then changes when the instance is replaced)."
  type        = string
  default     = null

  validation {
    condition     = var.private_ip == null || can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.private_ip))
    error_message = "private_ip must be null or an IPv4 address."
  }
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

variable "image_template" {
  description = <<-EOT
    The image template the instance is created from. Required: the module does not know
    what runs on the instance, the template does.
      ami_name_pattern  Name pattern of the AMI (the most recent match is used)
      ami_owners        Owners of the AMI (default amazon)
      user_data_file    Path of the user data template file (templatefile syntax)
      root_volume_size  Size of the root volume in GiB (default 8)
      root_volume_type  Type of the root volume (default gp3)
  EOT
  type = object({
    ami_name_pattern = string
    ami_owners       = optional(list(string), ["amazon"])
    user_data_file   = string
    root_volume_size = optional(number, 8)
    root_volume_type = optional(string, "gp3")
  })

  validation {
    condition     = fileexists(var.image_template.user_data_file)
    error_message = "image_template.user_data_file must be an existing file."
  }
}

variable "template_vars" {
  description = "Variables that the user data template can use (templatefile arguments)"
  type        = any
  default     = {}
}

variable "associate_public_ip" {
  description = "Give the instance a public IP. Needed to reach the internet (for example dnf) without a NAT Gateway."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Extra tags applied to every resource"
  type        = map(string)
  default     = {}
}
