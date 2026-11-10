variable "apps_dir" {
  description = "Folder with the app files (envs/<environment>/apps). Read when app_sources is null."
  type        = string
  default     = null
}

variable "app_sources" {
  description = "Optional: the app files as text (file name relative to the folder -> YAML text). When set, apps_dir is not read; used by the tests."
  type        = map(string)
  default     = null
}

variable "name" {
  description = "Platform name (common.name); target group names are '<name>-<backend>-tg'."
  type        = string
}

variable "vpc_b_subnet_cidr" {
  description = "Subnet of VPC-B; an explicit private_ip of an instance must be inside it."
  type        = string
}

variable "ec2_template_names" {
  description = "Names of the EC2 image templates the platform provides (templates/ec2/templates.yaml)."
  type        = list(string)
}

variable "platform_sections" {
  description = "Top-level keys of the platform file (values.yaml); used to report app sections left there."
  type        = list(string)
  default     = []
}

variable "max_asg_target_groups" {
  description = "How many target groups an Auto Scaling group can be attached to (Service Quotas, default 10)."
  type        = number
  default     = 10
}

variable "allowed_images" {
  description = "Repositories that workload images may come from (common.allowed_images). An entry that ends with / allows everything beneath that path (ghcr.io/your-org/); any other entry allows exactly that repository, with any tag or digest (nginx). null = no restriction."
  type        = list(string)
  default     = null
}
