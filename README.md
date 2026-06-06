# k8s-install

Ansible playbooks to install a production-ready Kubernetes **1.36** cluster (master + workers) with **Cilium 1.19.4** CNI. Works on both AWS cloud and on-premises servers (bare metal / VMware / Proxmox). Supports Ubuntu 22.04/24.04 and RHEL/CentOS 9.

## Stack

| Component | Version | Notes |
|-----------|---------|-------|
| Kubernetes | 1.36 | via pkgs.k8s.io |
| Cilium (CNI) | 1.19.4 | OCI Helm, eBPF mode |
| containerd | latest stable | SystemdCgroup, pause:3.10 |
| kube-proxy | disabled | replaced by Cilium eBPF |
| Helm | 3 (latest) | installed on master only |

## Project layout

```
.
├── site.yml                    # Main playbook — run this
├── reset.yml                   # Tear-down / reset playbook
├── group_vars/
│   └── all.yml                 # All tuneable variables
├── inventory/
│   ├── cloud.ini               # AWS inventory template
│   └── onprem.ini              # On-prem inventory template
└── roles/
    ├── common/                 # OS prep
    │   ├── tasks/main.yml      #   swap off, sysctl, kernel modules, limits,
    │   │                       #   timezone, packages, multipathd, AWS IMDSv2
    │   ├── handlers/main.yml
    │   └── templates/
    │       └── chrony.conf.j2  #   NTP config
    ├── containerd/             # Container runtime
    │   ├── tasks/main.yml      #   install, SystemdCgroup, pause:3.10, certs.d
    │   └── handlers/main.yml
    ├── kubernetes/             # kubeadm + kubelet + kubectl
    │   └── tasks/main.yml      #   apt/yum install, version hold
    ├── master/                 # Control plane
    │   └── tasks/main.yml      #   kubeadm init, Helm, Cilium, join command
    └── worker/                 # Data plane
        └── tasks/main.yml      #   kubeadm join
```

## Prerequisites

- Ansible >= 2.14 on your control machine
  ```bash
  pip install ansible
  ```
- Passwordless `sudo` on all target nodes (or set `ansible_become_pass`)
- SSH key access to all nodes
- Nodes running **Ubuntu 22.04 / 24.04** or **RHEL / CentOS 9**
- Kernel >= 5.10 (required for Cilium eBPF)
- For AWS: instances must have IMDSv2 enabled (default on current AMIs)

## Quick start

### 1. Edit your inventory

**AWS** — edit `inventory/cloud.ini`:
```ini
[masters]
master-1 ansible_host=10.0.1.10 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/key.pem

[workers]
worker-1 ansible_host=10.0.1.11 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/key.pem
worker-2 ansible_host=10.0.1.12 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/key.pem
```

**On-prem** — edit `inventory/onprem.ini`:
```ini
[masters]
master-1 ansible_host=192.168.1.10 ansible_user=ansible

[workers]
worker-1 ansible_host=192.168.1.11 ansible_user=ansible
worker-2 ansible_host=192.168.1.12 ansible_user=ansible
```

### 2. Tune variables (optional)

Edit `group_vars/all.yml`. Key settings:

| Variable | Default | Description |
|----------|---------|-------------|
| `kubernetes_version` | `1.36` | Kubernetes minor version |
| `cilium_version` | `1.19.4` | Cilium Helm chart version |
| `pod_network_cidr` | `10.0.0.0/8` | Pod CIDR (Cilium cluster-pool) |
| `service_cidr` | `10.96.0.0/12` | Service CIDR |
| `apiserver_advertise_address` | `` (auto) | Master IP; leave empty to auto-detect |
| `apiserver_extra_sans` | `[]` | Extra SANs (e.g. ELB hostname, VIP) |
| `cloud_provider` | `onprem` | `aws` / `onprem` — controls kubelet provider-id |
| `disable_host_firewall` | `false` | `true` on cloud (rely on SG rules) |
| `configure_ntp` | `true` | Install & configure chrony |
| `kubeadm_token_ttl` | `24h` | Worker join token lifetime |

### 3. Run

```bash
# AWS
ansible-playbook -i inventory/cloud.ini site.yml

# On-prem
ansible-playbook -i inventory/onprem.ini site.yml

# Dry-run (no changes applied)
ansible-playbook -i inventory/onprem.ini site.yml --check

# Limit to a single role for debugging
ansible-playbook -i inventory/cloud.ini site.yml --tags containerd
```

### 4. Verify

```bash
# On the master node
kubectl get nodes -o wide
kubectl get pods -n kube-system
cilium status
cilium connectivity test   # optional full connectivity check
```

Expected output after a successful install:
```
NAME       STATUS   ROLES           AGE   VERSION
master-1   Ready    control-plane   5m    v1.36.x
worker-1   Ready    <none>          3m    v1.36.x
worker-2   Ready    <none>          3m    v1.36.x
```

## Reset / tear down

```bash
# Resets kubeadm, removes CNI config, flushes iptables on all nodes
ansible-playbook -i inventory/<cloud|onprem>.ini reset.yml
```

## Cloud vs on-prem differences

| Concern | AWS (`cloud.ini`) | On-prem (`onprem.ini`) |
|---------|-------------------|------------------------|
| Firewall | `disable_host_firewall: true` — rely on Security Groups | `disable_host_firewall: false` — firewalld/ufw ports opened |
| Kubelet args | `--cloud-provider=external --provider-id=aws:///<az>/<id> --node-ip` via IMDSv2 | `--node-ip=<primary_ip>` |
| NTP | Usually pre-configured by AMI | chrony installed + configured |
| SSH auth | Key pair (`ansible_ssh_private_key_file`) | Key or password (`ansible_become_pass`) |
| API server SAN | Add ELB/NLB DNS to `apiserver_extra_sans` | Add keepalived VIP to `apiserver_extra_sans` |

## What each role does

### common
- Sets hostname, `/etc/hosts` entries, timezone (`Asia/Kolkata`)
- Full OS package upgrade
- Installs: `open-iscsi`, `nfs-common`, `conntrack`, `ipvsadm`, `chrony`, and more
- Loads kernel modules: `overlay`, `br_netfilter`, `iscsi_tcp`, `dm_crypt`
- Applies sysctl params (bridging, IP forwarding, eBPF JIT)
- Writes `/etc/security/limits.d/99-kubernetes.conf` (nofile/nproc 1048576)
- Disables swap (runtime + fstab)
- Masks `multipathd` (prevents iSCSI/Longhorn interference)
- On AWS: fetches IMDSv2 metadata and writes `KUBELET_EXTRA_ARGS` with provider-id

### containerd
- Installs `containerd.io` from Docker's official repo
- Generates default config, then patches:
  - `SystemdCgroup = true`
  - `sandbox_image = registry.k8s.io/pause:3.10`
  - `config_path = /etc/containerd/certs.d`

### kubernetes
- Adds `pkgs.k8s.io` apt/yum repo for the pinned minor version
- Installs and holds `kubeadm`, `kubelet`, `kubectl`

### master
- Runs `kubeadm init` (skips kube-proxy addon)
- Sets up kubeconfig for root and the Ansible user
- Installs Helm 3
- Installs Cilium via `oci://quay.io/cilium/charts/cilium` with `kubeProxyReplacement=true`
- Generates and stores the worker join command

### worker
- Runs `kubeadm join` using the token from the master

## Notes

- **kube-proxy is fully replaced** by Cilium eBPF (`--skip-phases=addon/kube-proxy` + `kubeProxyReplacement=true`).
- Cilium uses **cluster-pool IPAM** — pods get IPs from `pod_network_cidr`.
- `iscsi_tcp` and `dm_crypt` modules are loaded for storage solutions like Longhorn.
- `multipathd` is masked to prevent it from hijacking iSCSI device paths.
- Worker join tokens expire after `kubeadm_token_ttl` (default 24h). Re-run `master` role to regenerate.
