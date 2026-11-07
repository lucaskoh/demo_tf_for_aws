output "state_bucket_name" {
  description = "Use this as `bucket` in envs/demo/backend.tf"
  value       = aws_s3_bucket.state.id
}

output "plan_role_arn" {
  description = "Set as GitHub repository variable AWS_PLAN_ROLE_ARN"
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "Set as GitHub repository variable AWS_APPLY_ROLE_ARN"
  value       = aws_iam_role.apply.arn
}
