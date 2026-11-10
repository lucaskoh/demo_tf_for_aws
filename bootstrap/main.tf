terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # bootstrap itself uses local state (chicken-and-egg problem); never commit terraform.tfstate
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

locals {
  state_bucket_name = coalesce(var.state_bucket_name, "tfstate-${data.aws_caller_identity.current.account_id}-${var.region}")
  # Subject prefix of the GitHub OIDC token. Repos with immutable subject claims need the ID form.
  github_sub_prefix = coalesce(var.github_oidc_subject_prefix, "repo:${var.github_repo}")
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn

  # Every state key starts with this prefix: <prefix>/<environment>/<layer>/terraform.tfstate.
  # Keep it the same as in scripts/tf.sh.
  state_key_prefix = "aws-multi-vpc"
}

# ---------------------------------------------------------------------------
# Remote state bucket
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "state" {
  bucket = local.state_bucket_name
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# The bucket is encrypted with SSE-S3 (AES256). A customer managed KMS key adds a key policy and an audit
# trail, but costs about US$1 per month and every role that reads or writes the state would also need access
# to the key. That is a choice for a real environment, see docs/ci-cd.md (From demo to production).
# tfsec:ignore:aws-s3-encryption-customer-key
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Server access logs: who read or wrote the state bucket, and when. Delivered to the log bucket below.
resource "aws_s3_bucket_logging" "state" {
  bucket = aws_s3_bucket.state.id

  target_bucket = aws_s3_bucket.state_logs.id
  target_prefix = "${local.state_log_prefix}/"

  depends_on = [aws_s3_bucket_policy.state_logs]
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

data "aws_iam_policy_document" "state_bucket" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state_bucket.json
}

# ---------------------------------------------------------------------------
# Access logs of the state bucket
# ---------------------------------------------------------------------------
locals {
  state_log_prefix = "state-bucket"
}

# This bucket receives the access logs, so logging it too would write logs about the logs, forever.
# tfsec:ignore:aws-s3-enable-bucket-logging
resource "aws_s3_bucket" "state_logs" {
  bucket = "${local.state_bucket_name}-logs"
}

resource "aws_s3_bucket_public_access_block" "state_logs" {
  bucket                  = aws_s3_bucket.state_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# SSE-S3 for the same reason as for the state bucket (see above).
# tfsec:ignore:aws-s3-encryption-customer-key
resource "aws_s3_bucket_server_side_encryption_configuration" "state_logs" {
  bucket = aws_s3_bucket.state_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "state_logs" {
  bucket = aws_s3_bucket.state_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Logs are only useful for a while, and a few pennies per month is the point
resource "aws_s3_bucket_lifecycle_configuration" "state_logs" {
  bucket = aws_s3_bucket.state_logs.id

  rule {
    id     = "expire-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = 90
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "state_logs" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    resources = [
      aws_s3_bucket.state_logs.arn,
      "${aws_s3_bucket.state_logs.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # The S3 logging service may deliver the logs of the state bucket, and only those
  statement {
    sid     = "AllowAccessLogDelivery"
    effect  = "Allow"
    actions = ["s3:PutObject"]

    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }

    resources = ["${aws_s3_bucket.state_logs.arn}/${local.state_log_prefix}/*"]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.state.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "state_logs" {
  bucket = aws_s3_bucket.state_logs.id
  policy = data.aws_iam_policy_document.state_logs.json

  depends_on = [aws_s3_bucket_public_access_block.state_logs]
}

# ---------------------------------------------------------------------------
# GitHub Actions OIDC (no long-lived AWS access keys stored in GitHub)
# ---------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1

  url = "https://token.actions.githubusercontent.com"
}

# Plan role: used by pull requests only; read-only plus state access
data "aws_iam_policy_document" "plan_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.github_sub_prefix}:pull_request"]
    }
  }
}

resource "aws_iam_role" "plan" {
  name               = "github-terraform-plan"
  assume_role_policy = data.aws_iam_policy_document.plan_assume.json
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "state_access" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    # Read the state and the lock files of every environment and layer. The environment names are not
    # known here, so the resource has a wildcard, limited to the key prefix of the state.
    actions = ["s3:GetObject"]
    # tfsec:ignore:aws-iam-no-policy-wildcards
    resources = ["${aws_s3_bucket.state.arn}/${local.state_key_prefix}/*"]
  }

  statement {
    # plan acquires and releases the state lock, so it may write the lock files
    # (<state key>.tflock), but never the state itself: a pull request runs the workflow
    # of its own branch, and this role can be assumed by every pull request job
    actions = ["s3:PutObject", "s3:DeleteObject"]
    # tfsec:ignore:aws-iam-no-policy-wildcards
    resources = ["${aws_s3_bucket.state.arn}/${local.state_key_prefix}/*.tflock"]
  }
}

resource "aws_iam_role_policy" "plan_state" {
  name   = "state-access"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.state_access.json
}

# Apply role: only jobs bound to the GitHub environment "production" can assume it
data "aws_iam_policy_document" "apply_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.github_sub_prefix}:environment:production"]
    }
  }
}

resource "aws_iam_role" "apply" {
  name               = "github-terraform-apply"
  assume_role_policy = data.aws_iam_policy_document.apply_assume.json
}

# The demo uses AdministratorAccess for simplicity; use least privilege in real environments.
resource "aws_iam_role_policy_attachment" "apply_admin" {
  role       = aws_iam_role.apply.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
