output "alb_sg_id" {
  description = "Security group ID for the ALB"
  value       = aws_security_group.alb.id
}

output "eks_node_sg_id" {
  description = "Security group ID for the EKS worker nodes"
  value       = aws_security_group.eks_node.id
}

output "ec2_sg_id" {
  description = "Security group ID for the EC2 backend in VPC-B"
  value       = aws_security_group.ec2.id
}
