output "bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.this.id
}

output "object_urls" {
  description = "Public HTTPS URL of each uploaded object, keyed by object key"
  value = {
    for k, _ in aws_s3_object.files :
    k => "https://${aws_s3_bucket.this.bucket_regional_domain_name}/${k}"
  }
}
