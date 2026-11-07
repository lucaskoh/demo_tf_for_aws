resource "aws_lb" "this" {
  name               = "${var.name}-nlb"
  load_balancer_type = "network"
  internal           = false
  subnets            = var.subnet_ids

  tags = merge(var.tags, { Name = "${var.name}-nlb" })
}

# Target group whose target is the ALB itself
resource "aws_lb_target_group" "alb" {
  name        = "${var.name}-alb-tg"
  port        = 80
  protocol    = "TCP"
  target_type = "alb"
  vpc_id      = var.vpc_id

  # The ALB answers 404 on "/" (its default action), which still proves it is alive.
  health_check {
    protocol            = "HTTP"
    port                = "80"
    path                = "/"
    matcher             = "200-404"
    interval            = 30
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = merge(var.tags, { Name = "${var.name}-alb-tg" })
}

resource "aws_lb_target_group_attachment" "alb" {
  target_group_arn = aws_lb_target_group.alb.arn
  target_id        = var.alb_arn
  port             = 80
}

resource "aws_lb_listener" "tcp_80" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb.arn
  }

  tags = var.tags
}
