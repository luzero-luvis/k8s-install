# k8s-install

Ansible playbooks to install a production-ready Kubernetes **1.36** cluster with **Cilium 1.19.4** CNI.
Runs on both **AWS** and **on-premises** servers (bare metal, VMware, Proxmox).

Supported OS:
- Ubuntu 22.04 (Jammy) / 24.04 (Noble)
- Debian 12 (Bookworm)
- RHEL 9 / Rocky Linux 9 / AlmaLinux 9

---

## Stack

| Component | Version | Notes |
|-----------|---------|-------|
| Kubernetes | 1.36 | via pkgs.k8s.io |
| Cilium | 1.19.4 | OCI Helm, full eBPF mode |
| containerd | latest stable | SystemdCgroup, pause:3.10, certs.d |
| kube-proxy | **disabled** | replaced by Cilium eBPF |
| Helm | 3.17.3 | installed on master only |

---

## Project layout

```
.
├── ansible.cfg                       # Pipelining, YAML output, SSH tuning
├── requirements.yml                  # Ansible Galaxy collections
├── site.yml                          # Main playbook
├── reset.yml                         # Tear-down playbook
├── group_vars/
│   └── all.yml                       # All variables with defaults
├── inventory/
│   ├── cloud.ini                     # AWS template
│   └── onprem.ini                    # On-prem template
└── roles/
    ├── common/                       # OS preparation (all nodes)
    │   ├── tasks/main.yml
    │   ├── handlers/main.yml
    │   ├── templates/chrony.conf.j2
    │   └── meta/main.yml
    ├── containerd/                   # Container runtime
    │   ├── tasks/main.yml
    │   ├── handlers/main.yml
    │   └── meta/main.yml
    ├── kubernetes/                   # kubeadm + kubelet + kubectl
    │   ├── tasks/main.yml
    │   └── meta/main.yml
    ├── master/                       # Control plane init + Cilium
    │   ├── tasks/main.yml
    │   ├── templates/kubeadm-init.yaml.j2
    │   └── meta/main.yml
    └── worker/                       # Node join
        ├── tasks/main.yml
        └── meta/main.yml
```

---

## Prerequisites

**Control machine** (your laptop / jump host):
```bash
pip install ansible
ansible-galaxy collection install -r requirements.yml
```

**All target nodes** must have:
- Passwordless `sudo` for the Ansible user
- SSH key access from the control machine
- Kernel >= 5.10 (required for Cilium eBPF — check with `uname -r`)
- Internet access (or a local mirror — see Air-gap section below)

---

## Quick start

### Step 1 — Create your inventory from the example templates

Inventory `.ini` files are gitignored (they contain real IPs and key paths).
Copy the example files and fill in your values:

```bash
cp inventory/cloud.ini.example   inventory/cloud.ini   # for AWS
cp inventory/onprem.ini.example  inventory/onprem.ini  # for on-prem
```

**AWS** (`inventory/cloud.ini`):
```ini
[masters]
master-1 ansible_host=10.0.1.10 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/key.pem

[workers]
worker-1 ansible_host=10.0.1.11 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/key.pem
worker-2 ansible_host=10.0.1.12 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/key.pem

[k8s_cluster:children]
masters
workers

[k8s_cluster:vars]
cloud_provider=aws
disable_host_firewall=true
```

**On-prem** (`inventory/onprem.ini`):
```ini
[masters]
master-1 ansible_host=192.168.1.10 ansible_user=ansible

[workers]
worker-1 ansible_host=192.168.1.11 ansible_user=ansible
worker-2 ansible_host=192.168.1.12 ansible_user=ansible

[k8s_cluster:children]
masters
workers

[k8s_cluster:vars]
# ansible_become_pass=secret    # uncomment if sudo needs a password
```

**Multi-NIC on-prem** — if your servers have separate management / cluster NICs,
set `node_ip` per host so kubelet advertises the right IP:
```ini
[masters]
master-1 ansible_host=192.168.1.10 ansible_user=ansible node_ip=10.10.0.10

[workers]
worker-1 ansible_host=192.168.1.11 ansible_user=ansible node_ip=10.10.0.11
```

### Step 2 — Tune variables (optional)

Edit `group_vars/all.yml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `kubernetes_version` | `1.36` | Kubernetes minor version |
| `cilium_version` | `1.19.4` | Cilium Helm chart version |
| `helm_version` | `3.17.3` | Helm binary version |
| `pod_network_cidr` | `10.0.0.0/8` | Pod CIDR (Cilium cluster-pool IPAM) |
| `service_cidr` | `10.96.0.0/12` | Kubernetes Service CIDR |
| `apiserver_advertise_address` | `` (auto) | Master IP for API server; leave empty to auto-detect |
| `apiserver_extra_sans` | `[]` | Extra SANs (e.g. load-balancer hostname, VIP) |
| `cloud_provider` | `onprem` | `aws` or `onprem` — controls kubelet `--provider-id` |
| `node_ip` | `ansible_default_ipv4.address` | Override per-host if multiple NICs present |
| `disable_host_firewall` | `false` | `true` on cloud (rely on Security Groups) |
| `configure_ntp` | `true` | Install + configure chrony |
| `selinux_state` | `permissive` | RHEL only: `permissive` or `enforcing` |
| `kubeadm_token_ttl` | `24h` | Worker join token lifetime |

### Step 3 — Run

```bash
# Install Ansible collections first (one-time)
ansible-galaxy collection install -r requirements.yml

# On-prem
ansible-playbook -i inventory/onprem.ini site.yml

# AWS
ansible-playbook -i inventory/cloud.ini site.yml

# Dry-run (no changes applied)
ansible-playbook -i inventory/onprem.ini site.yml --check

# Run only specific roles using tags
ansible-playbook -i inventory/onprem.ini site.yml --tags containerd
ansible-playbook -i inventory/onprem.ini site.yml --tags cilium
ansible-playbook -i inventory/onprem.ini site.yml --tags firewall
ansible-playbook -i inventory/onprem.ini site.yml --tags ntp
```

### Step 4 — Verify

```bash
# From the master node
kubectl get nodes -o wide
kubectl get pods -n kube-system
cilium status
```

Expected output after a healthy install:
```
NAME       STATUS   ROLES           AGE   VERSION
master-1   Ready    control-plane   5m    v1.36.x
worker-1   Ready    <none>          3m    v1.36.x
worker-2   Ready    <none>          3m    v1.36.x
```

---

## Reset / tear down

```bash
ansible-playbook -i inventory/<cloud|onprem>.ini reset.yml
```

Resets kubeadm, removes CNI config, flushes iptables on every node.

---

## Role-by-role breakdown

### common
What it does on **every node**:
- Sets hostname + `/etc/hosts` entries
- Sets timezone to `Asia/Kolkata`
- Full OS package upgrade
- Installs: `open-iscsi`, `nfs-common`, `conntrack`/`conntrack-tools`, `ipvsadm`, `chrony`, and more
- Loads kernel modules: `overlay`, `br_netfilter`, `iscsi_tcp`, `dm_crypt`
- Applies sysctl params (bridging, IP forwarding, eBPF JIT)
- Writes `/etc/security/limits.d/99-kubernetes.conf` (nofile/nproc = 1048576)
- Disables swap permanently
- Masks `multipathd` (prevents iSCSI/Longhorn interference)
- Starts `iscsid`
- Writes `KUBELET_EXTRA_ARGS` to the OS-correct file (`/etc/default/kubelet` on Debian, `/etc/sysconfig/kubelet` on RHEL)
- **AWS only**: fetches IMDSv2 metadata, adds `--cloud-provider=external --provider-id=aws:///az/id`
- **RHEL only**: sets SELinux to `permissive` (configurable)
- **Firewall**: opens required ports via firewalld (RHEL) or ufw (Debian); or disables both for cloud SG-only setups

### containerd
- Downloads Docker GPG key and repo using `ansible_distribution` (handles Ubuntu vs Debian vs RHEL vs Rocky/Alma)
- Installs `containerd.io`
- Patches config: `SystemdCgroup = true`, `sandbox_image = registry.k8s.io/pause:3.10`, `config_path = /etc/containerd/certs.d`

### kubernetes
- Adds `pkgs.k8s.io` apt/yum repo pinned to the configured minor version
- Installs `kubeadm`, `kubelet`, `kubectl` and version-holds them

### master
- Writes a versioned `kubeadm-init.yaml` (kubeadm config file — not CLI flags)
- Runs `kubeadm init`, skipping `addon/kube-proxy`
- Sets up kubeconfig for root and the Ansible user
- Installs Helm 3 (pinned version, verified binary)
- Installs Cilium via `oci://quay.io/cilium/charts/cilium` with `kubeProxyReplacement=true`
- Generates and stores the worker join command

### worker
- Runs `kubeadm join` using the join command from the master

---

## Cloud vs on-prem reference

| Concern | AWS | On-prem (Ubuntu) | On-prem (RHEL) |
|---------|-----|-----------------|----------------|
| Firewall | SG rules — `disable_host_firewall: true` | ufw — ports opened automatically | firewalld — ports opened automatically |
| Kubelet node-ip | from IMDSv2 `local-ipv4` | `node_ip` var (default: primary NIC) | `node_ip` var (default: primary NIC) |
| Kubelet provider-id | `aws:///az/instance-id` | none | none |
| SELinux | N/A | N/A | set to `permissive` by default |
| NTP service | `chrony` (pre-installed on AMI) | `chrony` | `chronyd` |
| kubelet env file | `/etc/default/kubelet` | `/etc/default/kubelet` | `/etc/sysconfig/kubelet` |
| conntrack pkg | `conntrack` | `conntrack` | `conntrack-tools` |
| SSH auth | key pair | key or password | key or password |
| API server SAN | add ELB/NLB hostname to `apiserver_extra_sans` | add keepalived VIP | add keepalived VIP |

---

## Available tags

Run any subset of tasks with `--tags`:

| Tag | Scope |
|-----|-------|
| `common` | All common OS prep tasks |
| `packages` | Package install only |
| `ntp` | NTP / chrony configuration |
| `kernel` | Kernel module loading |
| `sysctl` | Kernel parameter tuning |
| `limits` | System limits (nofile/nproc) |
| `swap` | Swap disable |
| `storage` | multipathd masking, iscsid |
| `firewall` | Firewall port rules |
| `selinux` | SELinux mode (RHEL only) |
| `aws` | AWS IMDSv2 metadata tasks |
| `containerd` | Full containerd role |
| `kubernetes` | kubeadm/kubelet/kubectl install |
| `master` | Full master init |
| `helm` | Helm install only |
| `cilium` | Cilium install only |
| `worker` | Worker join only |

---

## Troubleshooting

**Nodes stuck in `NotReady`**
```bash
kubectl describe node <node-name>
journalctl -u kubelet -f
```
Usually means Cilium pods are not yet Running — wait 2-3 minutes.

**Cilium pods in `CrashLoopBackOff`**
```bash
kubectl logs -n kube-system -l k8s-app=cilium
```
Check kernel version: Cilium eBPF requires >= 5.10. Verify with `uname -r`.

**`kubeadm join` fails with "token not found"**
Tokens expire after `kubeadm_token_ttl` (default 24h). Re-run the master role to generate a new one:
```bash
ansible-playbook -i inventory/onprem.ini site.yml --tags master --limit masters
```

**Wrong IP advertised on multi-NIC servers**
Set `node_ip` per host in inventory:
```ini
worker-1 ansible_host=192.168.1.11 ansible_user=ansible node_ip=10.10.0.11
```

**SELinux blocking containerd on RHEL**
The role sets SELinux to `permissive` by default. Check with `getenforce`.
If still blocking, check audit logs: `ausearch -m avc -ts recent`.

---

## Known limitations

- **Air-gapped environments**: not supported out of the box. You would need a local mirror for `pkgs.k8s.io`, `download.docker.com`, and a private registry for Helm/Cilium images.
- **HA control plane**: only single-master is configured here. For HA, you need an external load balancer and `apiserver_advertise_address` set to the VIP.
- **Windows nodes**: not supported.
