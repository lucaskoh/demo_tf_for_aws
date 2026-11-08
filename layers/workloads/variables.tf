variable "environment" {
  description = "Name of the environment: the folder under envs/ whose values.yaml is used. Set by scripts/tf.sh."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{1,20}$", var.environment))
    error_message = "environment must be 1-20 characters: lowercase letters, digits and hyphens."
  }
}
