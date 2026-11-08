output "alb_arn" {
  description = "ALB ARN. Waits for the listener, because an NLB can only register an ALB that already has a listener on the target port."
  value       = aws_lb.this.arn

  depends_on = [aws_lb_listener.this]
}

output "alb_dns_name" {
  description = "DNS name of the ALB"
  value       = aws_lb.this.dns_name
}

output "listener_arn" {
  description = "ARN of the listener"
  value       = aws_lb_listener.this.arn
}
