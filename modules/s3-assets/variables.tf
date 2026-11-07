variable "bucket_name" {
  description = "Globally unique S3 bucket name"
  type        = string
}

variable "files" {
  description = "Files to upload: object key => local file path"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Extra tags applied to every resource"
  type        = map(string)
  default     = {}
}
