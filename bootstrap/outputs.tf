output "state_bucket_name" {
  description = "Use this as `common.state_bucket` in envs/<environment>/values.yaml"
  value       = aws_s3_bucket.state.id
}

output "plan_role_arn" {
  description = "Set as GitHub repository secret AWS_PLAN_ROLE_ARN"
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "Set as GitHub repository secret AWS_APPLY_ROLE_ARN"
  value       = aws_iam_role.apply.arn
}

output "state_logs_bucket_name" {
  description = "Bucket with the access logs of the state bucket (kept for 90 days)"
  value       = aws_s3_bucket.state_logs.id
}
