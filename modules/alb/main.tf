locals {
  # Targets that are registered one by one: "<group key>-<index>" => target
  ip_targets = merge([
    for k, tg in var.target_groups : {
      for i, ip in tg.ip_targets : "${k}-${i}" => { group = k, ip = ip }
    }
  ]...)

  # Groups backed by an Auto Scaling Group
  asg_groups = { for k, tg in var.target_groups : k => tg if tg.target_type == "instance" }
}

resource "aws_lb" "this" {
  name                       = "${var.name}-alb"
  load_balancer_type         = "application"
  internal                   = var.internal
  security_groups            = [var.sg_id]
  subnets                    = var.subnet_ids
  drop_invalid_header_fields = var.drop_invalid_header_fields

  tags = merge(var.tags, { Name = "${var.name}-alb" })
}

# Requests that match no rule get the fixed default response
resource "aws_lb_listener" "this" {
  load_balancer_arn = aws_lb.this.arn
  port              = var.listener_port
  protocol          = var.listener_protocol

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = var.default_response.content_type
      message_body = var.default_response.message_body
      status_code  = var.default_response.status_code
    }
  }

  tags = var.tags
}

resource "aws_lb_target_group" "this" {
  for_each = var.target_groups

  name        = "${var.name}-${each.key}-tg"
  port        = each.value.port
  protocol    = each.value.protocol
  target_type = each.value.target_type
  vpc_id      = var.vpc_id # also for IP targets that live in a peered VPC

  health_check {
    path                = each.value.health_check.path
    matcher             = each.value.health_check.matcher
    interval            = each.value.health_check.interval
    timeout             = each.value.health_check.timeout
    healthy_threshold   = each.value.health_check.healthy_threshold
    unhealthy_threshold = each.value.health_check.unhealthy_threshold
  }

  tags = merge(var.tags, { Name = "${var.name}-${each.key}-tg" })
}

# Registers every instance of the Auto Scaling Group automatically (including
# replacements), so the AWS Load Balancer Controller is not needed.
resource "aws_autoscaling_attachment" "this" {
  for_each = local.asg_groups

  autoscaling_group_name = each.value.autoscaling_group_name
  lb_target_group_arn    = aws_lb_target_group.this[each.key].arn
}

resource "aws_lb_target_group_attachment" "this" {
  for_each = local.ip_targets

  target_group_arn  = aws_lb_target_group.this[each.value.group].arn
  target_id         = each.value.ip
  port              = var.target_groups[each.value.group].port
  availability_zone = "all" # required when the IP is outside the target group's VPC
}

# Path-based routing
resource "aws_lb_listener_rule" "this" {
  for_each = var.target_groups

  listener_arn = aws_lb_listener.this.arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[each.key].arn
  }

  condition {
    path_pattern {
      values = each.value.path_patterns
    }
  }

  tags = var.tags
}
