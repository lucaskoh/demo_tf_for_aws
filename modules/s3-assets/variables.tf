variable "bucket_name" {
  description = "Globally unique S3 bucket name"
  type        = string
}

variable "files" {
  description = "Files to upload: object key => local file path"
  type        = map(string)
  default     = {}
}

variable "force_destroy" {
  description = "Allow destroying the bucket even when it still contains objects (demo only)"
  type        = bool
  default     = true
}

variable "public_read" {
  description = "Allow anyone to read the objects through a bucket policy. Demo only; use CloudFront with Origin Access Control in production."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Extra tags applied to every resource"
  type        = map(string)
  default     = {}
}
