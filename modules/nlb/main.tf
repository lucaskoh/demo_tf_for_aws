resource "aws_lb" "this" {
  name               = "${var.name}-nlb"
  load_balancer_type = "network"
  internal           = var.internal
  subnets            = var.subnet_ids

  tags = merge(var.tags, { Name = "${var.name}-nlb" })
}

# Target group whose target is the ALB itself
resource "aws_lb_target_group" "alb" {
  name        = "${var.name}-alb-tg"
  port        = var.target_port
  protocol    = "TCP"
  target_type = "alb"
  vpc_id      = var.vpc_id

  health_check {
    protocol            = "HTTP"
    port                = tostring(var.target_port)
    path                = var.health_check.path
    matcher             = var.health_check.matcher
    interval            = var.health_check.interval
    healthy_threshold   = var.health_check.healthy_threshold
    unhealthy_threshold = var.health_check.unhealthy_threshold
  }

  tags = merge(var.tags, { Name = "${var.name}-alb-tg" })
}

# Only does something on destroy. Resources are destroyed in the reverse order of
# their dependencies, so the order here is:
#   attachment (ALB leaves the NLB target group) -> this wait -> ALB listener.
# The wait depends on the ALB listener through var.alb_arn (the ALB module's
# alb_arn output waits for its listener). The attachment depends on the wait.
resource "time_sleep" "alb_deregistration" {
  destroy_duration = var.deregistration_wait

  triggers = {
    alb_arn = var.alb_arn
  }
}

resource "aws_lb_target_group_attachment" "alb" {
  target_group_arn = aws_lb_target_group.alb.arn
  target_id        = var.alb_arn
  port             = var.target_port

  # Must be created after the wait, so it is destroyed before it (see above)
  depends_on = [time_sleep.alb_deregistration]
}

resource "aws_lb_listener" "this" {
  load_balancer_arn = aws_lb.this.arn
  port              = var.listener_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb.arn
  }

  tags = var.tags
}
