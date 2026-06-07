variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "cluster_name" {
  description = "Cluster name — used for resource naming and tags"
  type        = string
  default     = "k8s-test"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "master_instance_type" {
  description = "EC2 instance type for the master node"
  type        = string
  default     = "t3.medium"
}

variable "worker_instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}

variable "disk_size_gb" {
  description = "Root EBS volume size in GB for all nodes"
  type        = number
  default     = 30
}

# ── SSH key — choose ONE of the two modes below ───────────────────────────
#
#   Mode A — upload your local public key (default):
#     set existing_key_pair_name = ""
#     set ssh_public_key_path    = "~/.ssh/id_rsa.pub"
#
#   Mode B — use a key pair already in AWS:
#     set existing_key_pair_name = "my-existing-key"
#     ssh_public_key_path is ignored in this mode
#
variable "existing_key_pair_name" {
  description = "Name of an existing AWS key pair to use. Leave empty to upload a new public key."
  type        = string
  default     = ""
}

variable "ssh_public_key_path" {
  description = "Path to local SSH public key — used only when existing_key_pair_name is empty"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key — written into the Ansible inventory"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH into nodes — restrict to your IP in production"
  type        = string
  default     = "0.0.0.0/0"
}

variable "allowed_api_cidr" {
  description = "CIDR allowed to reach the Kubernetes API server (port 6443)"
  type        = string
  default     = "0.0.0.0/0"
}
