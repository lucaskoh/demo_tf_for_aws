resource "aws_lb" "this" {
  name                       = "${var.name}-alb"
  load_balancer_type         = "application"
  internal                   = var.internal
  security_groups            = [var.sg_id]
  subnets                    = var.subnet_ids
  drop_invalid_header_fields = true

  tags = merge(var.tags, { Name = "${var.name}-alb" })
}

# ---------------------------------------------------------------------------
# Listener: anything that is not /html1 or /html2 gets a 404 with a hint
# ---------------------------------------------------------------------------
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Not found. Try /html1 (EKS) or /html2 (EC2)."
      status_code  = "404"
    }
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Target group 1: EKS worker nodes (instance targets on the NodePort)
# ---------------------------------------------------------------------------
resource "aws_lb_target_group" "eks" {
  name        = "${var.name}-eks-tg"
  port        = var.node_port
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = var.vpc_id

  health_check {
    path                = "/html1/index.html"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(var.tags, { Name = "${var.name}-eks-tg" })
}

# Registers every node of the managed node group automatically (including
# Spot replacements), so the AWS Load Balancer Controller is not needed.
resource "aws_autoscaling_attachment" "eks" {
  autoscaling_group_name = var.eks_asg_name
  lb_target_group_arn    = aws_lb_target_group.eks.arn
}

# ---------------------------------------------------------------------------
# Target group 2: EC2 in the peered VPC-B (IP target)
# ---------------------------------------------------------------------------
resource "aws_lb_target_group" "ec2" {
  name        = "${var.name}-ec2-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id # the target group lives in VPC-A, the IP target is in VPC-B

  health_check {
    path                = "/html2/index.html"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(var.tags, { Name = "${var.name}-ec2-tg" })
}

resource "aws_lb_target_group_attachment" "ec2" {
  target_group_arn  = aws_lb_target_group.ec2.arn
  target_id         = var.ec2_private_ip
  port              = 80
  availability_zone = "all" # required when the IP is outside the target group's VPC
}

# ---------------------------------------------------------------------------
# Path-based routing
# ---------------------------------------------------------------------------
resource "aws_lb_listener_rule" "html1" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.eks.arn
  }

  condition {
    path_pattern {
      values = ["/html1", "/html1/*"]
    }
  }

  tags = var.tags
}

resource "aws_lb_listener_rule" "html2" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ec2.arn
  }

  condition {
    path_pattern {
      values = ["/html2", "/html2/*"]
    }
  }

  tags = var.tags
}
