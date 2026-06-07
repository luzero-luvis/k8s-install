# ── Cluster-internal SG ────────────────────────────────────────────────────
# All nodes are in this SG. The self-referencing rule allows unrestricted
# node-to-node traffic required by Cilium eBPF and kubelet communication.

resource "aws_security_group" "cluster" {
  name        = "${var.cluster_name}-cluster"
  description = "Allow all traffic between cluster nodes"
  vpc_id      = aws_vpc.k8s.id

  tags = { Name = "${var.cluster_name}-cluster-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "cluster_self" {
  security_group_id            = aws_security_group.cluster.id
  referenced_security_group_id = aws_security_group.cluster.id
  ip_protocol                  = "-1"
  description                  = "All traffic from cluster nodes"
}

resource "aws_vpc_security_group_egress_rule" "cluster_all_out" {
  security_group_id = aws_security_group.cluster.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All outbound"
}

# ── Master SG ──────────────────────────────────────────────────────────────

resource "aws_security_group" "master" {
  name        = "${var.cluster_name}-master"
  description = "Kubernetes master node"
  vpc_id      = aws_vpc.k8s.id

  tags = { Name = "${var.cluster_name}-master-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "master_ssh" {
  security_group_id = aws_security_group.master.id
  cidr_ipv4         = var.allowed_ssh_cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  description       = "SSH from Ansible control machine"
}

resource "aws_vpc_security_group_ingress_rule" "master_api" {
  security_group_id = aws_security_group.master.id
  cidr_ipv4         = var.allowed_api_cidr
  from_port         = 6443
  to_port           = 6443
  ip_protocol       = "tcp"
  description       = "Kubernetes API server"
}

resource "aws_vpc_security_group_egress_rule" "master_all_out" {
  security_group_id = aws_security_group.master.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All outbound"
}

# ── Worker SG ──────────────────────────────────────────────────────────────

resource "aws_security_group" "worker" {
  name        = "${var.cluster_name}-worker"
  description = "Kubernetes worker node"
  vpc_id      = aws_vpc.k8s.id

  tags = { Name = "${var.cluster_name}-worker-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "worker_ssh" {
  security_group_id = aws_security_group.worker.id
  cidr_ipv4         = var.allowed_ssh_cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  description       = "SSH from Ansible control machine"
}

resource "aws_vpc_security_group_ingress_rule" "worker_nodeport" {
  security_group_id = aws_security_group.worker.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 30000
  to_port           = 32767
  ip_protocol       = "tcp"
  description       = "NodePort services"
}

resource "aws_vpc_security_group_egress_rule" "worker_all_out" {
  security_group_id = aws_security_group.worker.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All outbound"
}
