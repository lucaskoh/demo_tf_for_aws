data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

locals {
  index_html = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>EC2</title></head><body><h1>Hello from EC2 (VPC-B via VPC Peering)</h1><img src=\"${var.image_url}\" alt=\"EC2 logo\" width=\"200\"></body></html>"

  user_data = <<-EOT
    #!/bin/bash
    set -euxo pipefail
    dnf install -y nginx
    mkdir -p /usr/share/nginx/html/html2
    cat > /usr/share/nginx/html/html2/index.html <<'HTML'
    ${local.index_html}
    HTML
    systemctl enable --now nginx
  EOT
}

resource "aws_instance" "this" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  private_ip                  = var.private_ip
  vpc_security_group_ids      = var.security_group_ids
  associate_public_ip_address = true # needed to reach the internet (dnf) without a NAT Gateway
  user_data                   = local.user_data
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 only
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
  }

  tags = merge(var.tags, { Name = var.name })
}
