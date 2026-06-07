# Auto-generates ../inventory/cloud.ini after `terraform apply`.
# The file is gitignored — safe to contain real IPs and key paths.

resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/templates/inventory.tpl", {
    master_name          = "master-1"
    master_public_ip     = aws_instance.master.public_ip
    ssh_private_key_path = var.ssh_private_key_path
    workers = [for i, w in aws_instance.workers : {
      name      = "worker-${i + 1}"
      public_ip = w.public_ip
    }]
  })
  filename        = "${path.module}/../inventory/cloud.ini"
  file_permission = "0644"

  depends_on = [aws_instance.master, aws_instance.workers]
}
