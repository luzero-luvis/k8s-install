data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ── Key pair ───────────────────────────────────────────────────────────────
# Mode A: upload local public key → creates a new AWS key pair
# Mode B: use an existing AWS key pair by name (set existing_key_pair_name)

resource "aws_key_pair" "k8s" {
  count      = var.existing_key_pair_name == "" ? 1 : 0
  key_name   = "${var.cluster_name}-key"
  public_key = file(var.ssh_public_key_path)

  tags = { Name = "${var.cluster_name}-key" }
}

data "aws_key_pair" "existing" {
  count    = var.existing_key_pair_name != "" ? 1 : 0
  key_name = var.existing_key_pair_name
}

locals {
  key_name = var.existing_key_pair_name != "" ? data.aws_key_pair.existing[0].key_name : aws_key_pair.k8s[0].key_name
}

# ── Master ─────────────────────────────────────────────────────────────────

resource "aws_instance" "master" {
  ami                  = data.aws_ami.ubuntu.id
  instance_type        = var.master_instance_type
  subnet_id            = aws_subnet.k8s.id
  key_name             = local.key_name
  iam_instance_profile = aws_iam_instance_profile.k8s_node.name

  vpc_security_group_ids = [
    aws_security_group.cluster.id,
    aws_security_group.master.id,
  ]

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.disk_size_gb
    encrypted             = true
    delete_on_termination = true
  }

  # IMDSv2 required — Ansible common role fetches instance metadata via token
  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2
  }

  user_data = <<-EOF
    #!/bin/bash
    hostnamectl set-hostname master-1
  EOF

  tags = { Name = "${var.cluster_name}-master-1", Role = "master" }
}

# ── Workers ────────────────────────────────────────────────────────────────

resource "aws_instance" "workers" {
  count                = var.worker_count
  ami                  = data.aws_ami.ubuntu.id
  instance_type        = var.worker_instance_type
  subnet_id            = aws_subnet.k8s.id
  key_name             = local.key_name
  iam_instance_profile = aws_iam_instance_profile.k8s_node.name

  vpc_security_group_ids = [
    aws_security_group.cluster.id,
    aws_security_group.worker.id,
  ]

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.disk_size_gb
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2
  }

  user_data = <<-EOF
    #!/bin/bash
    hostnamectl set-hostname worker-${count.index + 1}
  EOF

  tags = { Name = "${var.cluster_name}-worker-${count.index + 1}", Role = "worker" }
}
