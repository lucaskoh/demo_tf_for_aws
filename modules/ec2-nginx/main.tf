data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = [var.ami_name_pattern]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

locals {
  # The same page is written to every path. This is built outside the user_data heredoc on
  # purpose: a heredoc that contains %{ } template directives keeps its indentation, which
  # would break the script.
  page_commands = join("\n", [
    for p in var.path_prefixes : <<-EOC
      mkdir -p /usr/share/nginx/html/${p}
      cat > /usr/share/nginx/html/${p}/index.html <<'HTML'
      ${var.page_html}
      HTML
    EOC
  ])

  user_data = <<-EOT
    #!/bin/bash
    set -euxo pipefail
    dnf install -y nginx
    # No-op for port 80 (the default); otherwise move the default server to http_port
    sed -i -E 's/^(\s*listen\s+(\[::\]:)?)80;/\1${var.http_port};/' /etc/nginx/nginx.conf
    ${local.page_commands}
    systemctl enable --now nginx
  EOT
}

resource "aws_instance" "this" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  private_ip                  = var.private_ip
  vpc_security_group_ids      = var.security_group_ids
  associate_public_ip_address = var.associate_public_ip
  user_data                   = local.user_data
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 only
  }

  root_block_device {
    volume_type = var.root_volume_type
    volume_size = var.root_volume_size
    encrypted   = true
  }

  tags = merge(var.tags, { Name = var.name })
}
