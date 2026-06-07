output "master_public_ip" {
  description = "Master node public IP"
  value       = aws_instance.master.public_ip
}

output "master_private_ip" {
  description = "Master node private IP (used as API server advertise address)"
  value       = aws_instance.master.private_ip
}

output "worker_public_ips" {
  description = "Worker node public IPs"
  value       = aws_instance.workers[*].public_ip
}

output "worker_private_ips" {
  description = "Worker node private IPs"
  value       = aws_instance.workers[*].private_ip
}

output "inventory_path" {
  description = "Path to the generated Ansible inventory"
  value       = "${path.module}/../inventory/cloud.ini"
}

output "next_steps" {
  description = "Commands to run after terraform apply"
  value       = <<-EOT

    ── Next steps ──────────────────────────────────────────────────────────

    1. Wait ~30s for SSH to come up on all nodes, then run Ansible:

       cd ..
       ansible-galaxy collection install -r requirements.yml
       ansible-playbook -i inventory/cloud.ini site.yml

    2. After the playbook completes, use kubectl locally:

       export KUBECONFIG=$(pwd)/kubeconfig
       kubectl get nodes -o wide

    3. To tear everything down:

       ansible-playbook -i inventory/cloud.ini reset.yml
       cd terraform && terraform destroy

    ────────────────────────────────────────────────────────────────────────
  EOT
}
