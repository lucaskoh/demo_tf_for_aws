data "aws_ami" "this" {
  most_recent = true
  owners      = var.image_template.ami_owners

  filter {
    name   = "name"
    values = [var.image_template.ami_name_pattern]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_instance" "this" {
  ami                         = data.aws_ami.this.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  private_ip                  = var.private_ip
  vpc_security_group_ids      = var.security_group_ids
  associate_public_ip_address = var.associate_public_ip
  user_data                   = templatefile(var.image_template.user_data_file, var.template_vars)
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 only
  }

  root_block_device {
    volume_type = var.image_template.root_volume_type
    volume_size = var.image_template.root_volume_size
    encrypted   = true
  }

  tags = merge(var.tags, { Name = var.name })
}
