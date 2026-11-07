locals {
  content_types = {
    png  = "image/png"
    jpg  = "image/jpeg"
    jpeg = "image/jpeg"
    gif  = "image/gif"
    svg  = "image/svg+xml"
    webp = "image/webp"
  }
}

resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  force_destroy = true # demo bucket: allow destroy even when objects exist

  tags = merge(var.tags, { Name = var.bucket_name })
}

# Demo only: allow a public-read bucket policy so browsers can load the images
# directly. For production, use CloudFront with Origin Access Control instead.
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false
  restrict_public_buckets = false
}

data "aws_iam_policy_document" "public_read" {
  statement {
    sid       = "PublicReadObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.this.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }
}

resource "aws_s3_bucket_policy" "public_read" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.public_read.json

  depends_on = [aws_s3_bucket_public_access_block.this]
}

resource "aws_s3_object" "files" {
  for_each = var.files

  bucket       = aws_s3_bucket.this.id
  key          = each.key
  source       = each.value
  etag         = filemd5(each.value)
  content_type = try(local.content_types[lower(regex("[^.]+$", each.key))], "application/octet-stream")

  tags = var.tags
}
