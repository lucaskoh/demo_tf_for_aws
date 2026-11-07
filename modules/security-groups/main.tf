# ---------------------------------------------------------------------------
# Security groups (rules are separate resources to avoid circular references
# between alb-sg and eks-node-sg)
# ---------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "ALB: HTTP in from clients, out only to the backends"
  vpc_id      = var.vpc_a_id

  tags = merge(var.tags, { Name = "${var.name_prefix}-alb-sg" })
}

# Attach this IN ADDITION to the EKS cluster security group.
# The cluster SG keeps node <-> control plane / node <-> node traffic working.
resource "aws_security_group" "eks_node" {
  name        = "${var.name_prefix}-eks-node-sg"
  description = "EKS nodes: NodePort reachable only from the ALB"
  vpc_id      = var.vpc_a_id

  tags = merge(var.tags, { Name = "${var.name_prefix}-eks-node-sg" })
}

resource "aws_security_group" "ec2" {
  name        = "${var.name_prefix}-ec2-sg"
  description = "EC2 backend: HTTP only from VPC-A over the peering"
  vpc_id      = var.vpc_b_id

  tags = merge(var.tags, { Name = "${var.name_prefix}-ec2-sg" })
}

# ---------------------------------------------------------------------------
# alb-sg
# ---------------------------------------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from clients (via NLB)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_to_eks" {
  security_group_id            = aws_security_group.alb.id
  description                  = "To EKS nodes (NodePort)"
  referenced_security_group_id = aws_security_group.eks_node.id
  ip_protocol                  = "tcp"
  from_port                    = var.node_port
  to_port                      = var.node_port
}

resource "aws_vpc_security_group_egress_rule" "alb_to_ec2" {
  security_group_id = aws_security_group.alb.id
  description       = "To EC2 in VPC-B over the peering"
  cidr_ipv4         = var.vpc_b_cidr
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

# ---------------------------------------------------------------------------
# eks-node-sg
# ---------------------------------------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "eks_node_from_alb" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "NodePort from ALB only"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.node_port
  to_port                      = var.node_port
}

resource "aws_vpc_security_group_egress_rule" "eks_node_all" {
  security_group_id = aws_security_group.eks_node.id
  description       = "All outbound (pull images, reach AWS APIs)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ---------------------------------------------------------------------------
# ec2-sg
# ---------------------------------------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "ec2_from_vpc_a" {
  security_group_id = aws_security_group.ec2.id
  description       = "HTTP from VPC-A (ALB nodes) over the peering"
  cidr_ipv4         = var.vpc_a_cidr
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "ec2_all" {
  security_group_id = aws_security_group.ec2.id
  description       = "All outbound (install packages)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
