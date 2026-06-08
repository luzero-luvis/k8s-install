# Kubernetes Cluster Setup — Complete Beginner's Guide

This document explains everything in this project, word by word, in plain English.
No jargon without explanation. Read top to bottom — each section builds on the last.

---

## Table of Contents

1. [What Is This Project?](#what-is-this-project)
2. [The Big Picture — How It All Fits Together](#the-big-picture)
3. [Folder Structure](#folder-structure)
4. [File-by-File Explanation](#file-by-file-explanation)
   - [inventory/onprem.ini — The Address Book](#inventoryonpremini--the-address-book)
   - [ansible.cfg — Ansible's Own Settings](#ansiblecfg--ansibles-own-settings)
   - [group_vars/all.yml — Global Settings Panel](#group_varsallyml--global-settings-panel)
   - [requirements.yml — The Shopping List](#requirementsyml--the-shopping-list)
   - [site.yml — The Master Plan](#siteyml--the-master-plan)
   - [reset.yml — The Undo Button](#resetyml--the-undo-button)
5. [Roles — The Job Workers](#roles--the-job-workers)
   - [preflight — The Checklist](#preflight--the-checklist)
   - [common — OS Setup](#common--os-setup)
   - [containerd — Container Engine](#containerd--container-engine)
   - [kubernetes — Install k8s Tools](#kubernetes--install-k8s-tools)
   - [master — Start the Boss Computer](#master--start-the-boss-computer)
   - [worker — Connect Helper Computers](#worker--connect-helper-computers)
6. [Templates](#templates)
   - [kubeadm-init.yaml.j2](#kubeadm-inityamlj2)
   - [chrony.conf.j2](#chronyconfj2)
7. [Where to Start — Action Steps](#where-to-start--action-steps)
8. [The Full Flow When You Run It](#the-full-flow-when-you-run-it)
9. [Key Words Glossary](#key-words-glossary)

---

## What Is This Project?

You have **multiple computers**. You want to turn them into a **Kubernetes cluster**.

**What is a Kubernetes cluster?**
- One computer is the **BOSS** (called the `master` or `control plane`) — it gives orders and decides what runs where.
- Other computers are **WORKERS** — they receive orders from the boss and actually run your apps.
- Together they form a cluster — a team of computers that work as one unit.

**Why Kubernetes?**
- Run your apps as small containers (isolated mini-processes)
- If one computer crashes, Kubernetes automatically moves your apps to another
- Scale apps up or down with one command
- Rolling updates with zero downtime

**What is Ansible?**
Instead of logging into each computer and typing 200 commands manually, Ansible does it automatically. You tell Ansible: "here are my computers, here's what I want installed" — Ansible SSH-es into each computer and does everything for you.

---

## The Big Picture

```
YOUR LAPTOP (runs Ansible)
      |
      | SSH
      |
  ┌───▼────────┐      ┌──────────────┐      ┌──────────────┐
  │  master-1  │──────│   worker-1   │      │   worker-2   │
  │            │      │              │      │              │
  │ API Server │      │   kubelet    │      │   kubelet    │
  │ etcd (DB)  │      │  containerd  │      │  containerd  │
  │ Scheduler  │      │  Your Apps   │      │  Your Apps   │
  │ Controller │      └──────────────┘      └──────────────┘
  └────────────┘
```

- **master-1**: The brain. Runs the Kubernetes control plane (API server, database, scheduler).
- **worker-1, worker-2**: The muscle. Runs your actual applications (pods/containers).
- **Ansible**: Connects to all of them via SSH from your laptop and installs everything.

---

## Folder Structure

```
k8s-install/
│
├── inventory/           ← The ADDRESS BOOK (list of computers + their IPs)
│   ├── onprem.ini       ← For computers you own (bare metal, VMware, etc.)
│   └── cloud.ini.example← Example for AWS/cloud computers
│
├── group_vars/
│   └── all.yml          ← GLOBAL SETTINGS (applies to every computer)
│
├── site.yml             ← MASTER PLAYBOOK (runs everything in order)
├── reset.yml            ← UNDO BUTTON (tears down the whole cluster)
├── ansible.cfg          ← Ansible's own behavior settings
├── requirements.yml     ← Shopping list of extra Ansible tools to download
│
└── roles/               ← JOB WORKERS (each folder = one specific job)
    ├── preflight/       ← CHECK that computers are ready (before installing)
    ├── common/          ← PREPARE the OS on every computer
    ├── containerd/      ← INSTALL the container engine (containerd)
    ├── kubernetes/      ← INSTALL k8s tools (kubelet, kubeadm, kubectl)
    ├── master/          ← START Kubernetes on the boss computer
    └── worker/          ← CONNECT worker computers to the boss
```

---

## File-by-File Explanation

### `inventory/onprem.ini` — The Address Book

**Purpose**: Tells Ansible which computers exist and how to reach them.

```ini
[masters]
master-1 ansible_host=192.168.1.10 ansible_user=ansible
```

| Part | Meaning |
|------|---------|
| `[masters]` | A group name. Everything below this line belongs to the "masters" group. |
| `master-1` | The nickname you give this computer. Can be anything. |
| `ansible_host=192.168.1.10` | The actual IP address Ansible uses to SSH in. |
| `ansible_user=ansible` | The Linux username to log in as. Must have sudo access. |

```ini
[workers]
worker-1 ansible_host=192.168.1.11 ansible_user=ansible
worker-2 ansible_host=192.168.1.12 ansible_user=ansible
```

Same pattern — but these are the worker computers.

```ini
[k8s_cluster:children]
masters
workers
```

| Part | Meaning |
|------|---------|
| `[k8s_cluster:children]` | Create a **super-group** that contains smaller groups. |
| `:children` | This group is made OF other groups (not direct computers). |
| `masters` + `workers` | Both groups are included. Now `k8s_cluster` = everyone. |

```ini
[k8s_cluster:vars]
ansible_python_interpreter=/usr/bin/python3
```

| Part | Meaning |
|------|---------|
| `[k8s_cluster:vars]` | Settings that apply to every computer in k8s_cluster. |
| `ansible_python_interpreter=/usr/bin/python3` | Use Python 3 (not old Python 2) on remote machines. |

---

### `ansible.cfg` — Ansible's Own Settings

**Purpose**: Controls how Ansible behaves globally — its own config file.

```ini
[defaults]
inventory           = inventory/
```
Default location of the address book. If you don't pass `-i` flag, Ansible looks here.

```ini
roles_path          = roles/
```
Where to look for role folders (the job workers).

```ini
host_key_checking   = False
```
SSH normally asks "do you trust this new machine?" and waits for a human to type `yes`. `False` = skip that question so automation never gets stuck waiting.

```ini
retry_files_enabled = False
```
When a playbook fails, Ansible can write a `.retry` file listing failed computers. `False` = don't create these files (keeps things clean).

```ini
stdout_callback     = default
result_format       = yaml
```
How Ansible formats output in your terminal. `yaml` = clean, readable format.

```ini
callbacks_enabled   = profile_tasks, timer
```
Two extra plugins:
- `profile_tasks` = show how long each task took (find bottlenecks)
- `timer` = show total run time at the end

```ini
gathering           = smart
fact_caching        = memory
```
- `gathering` = "smart" means only collect computer info (OS, RAM, etc.) if not already known in this run.
- `fact_caching = memory` = keep that info in RAM during the run (gone when playbook finishes).

```ini
pipelining          = True
forks               = 10
```
- `pipelining` = bundle multiple SSH commands together — significantly faster.
- `forks = 10` = work on 10 computers simultaneously.

```ini
[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o ServerAliveInterval=30
```
| Option | Meaning |
|--------|---------|
| `ControlMaster=auto` | Reuse existing SSH connections instead of opening new ones every time. |
| `ControlPersist=60s` | Keep the SSH connection open for 60 seconds after the last command. |
| `ServerAliveInterval=30` | Send a "are you still there?" ping every 30 seconds to prevent connection drops. |

---

### `group_vars/all.yml` — Global Settings Panel

**Purpose**: Variables (settings) available to every computer and every task.

#### Kubernetes Version

```yaml
kubernetes_version: "1.36.1"
```
Which version to install. Like choosing Windows 11 vs 10 — be specific.

```yaml
kubernetes_repo_version: "{{ kubernetes_version.split('.')[:2] | join('.') }}"
```
Auto-calculates `"1.36"` from `"1.36.1"`. Package download servers use major.minor, not full version.

Breaking down the expression:
- `.split('.')` = break `"1.36.1"` into `["1", "36", "1"]`
- `[:2]` = take first 2 items → `["1", "36"]`
- `| join('.')` = join with dots → `"1.36"`

#### Container Runtime

```yaml
containerd_config_dir: /etc/containerd
```
Where containerd stores its config files on the computer.

#### Networking

```yaml
pod_network_cidr: "10.244.0.0/16"
service_cidr: "10.96.0.0/12"
```
| Setting | Meaning |
|---------|---------|
| `pod_network_cidr` | IP range for pods. `/16` = 65,536 available IPs. |
| `service_cidr` | IP range for Services. `/12` = ~1 million available IPs. |

**IMPORTANT**: These ranges must NOT overlap with your real network. If your office uses `10.244.x.x`, change this.

```yaml
cilium_version: "1.19.4"
```
Cilium = the networking brain. Connects all pods, replaces kube-proxy, uses eBPF for speed.

#### Environment Type

```yaml
cloud_provider: onprem
```
Are you running on your own computers (`onprem`) or AWS (`aws`)? This enables/disables AWS-specific steps.

```yaml
disable_host_firewall: true
```
- `true` = turn off the computer's built-in firewall (use when cloud security groups or no firewall needed)
- `false` = keep firewall on and let Ansible open specific Kubernetes ports

#### Time Sync

```yaml
configure_ntp: true
ntp_servers:
  - "0.pool.ntp.org"
  - "1.pool.ntp.org"
```
Keep all clocks in sync. Critical for Kubernetes — certificates expire by time, tokens expire by time, logs need matching timestamps.

---

### `requirements.yml` — The Shopping List

**Purpose**: Extra Ansible tools (collections) to download before running the playbook.

```yaml
collections:
  - name: ansible.posix
    version: ">=1.5"
  - name: community.general
    version: ">=8.0"
```

| Collection | Provides |
|------------|---------|
| `ansible.posix` | Modules for Linux system settings: `sysctl`, `firewalld`, `selinux` |
| `community.general` | Hundreds of extra modules: `timezone`, `modprobe`, `ufw`, `dpkg_selections` |

**How to install**: Run once before first playbook run:
```bash
ansible-galaxy collection install -r requirements.yml
```

---

### `site.yml` — The Master Plan

**Purpose**: The main playbook. Running this file installs the complete cluster.

```yaml
- name: Pre-flight checks (all nodes)
  hosts: k8s_cluster
  become: true
  gather_facts: true
  tags: [preflight]
  roles:
    - preflight
```

Every "play" (section) has the same structure:

| Key | Meaning |
|-----|---------|
| `name` | Label shown in terminal when this runs |
| `hosts` | Which computers to run this on |
| `become: true` | Use `sudo` — run as root/admin |
| `gather_facts` | Collect computer info first (OS, RAM, IP, etc.) |
| `tags` | Labels so you can run just this section with `--tags` |
| `roles` | Which role folders to execute |

**The 5 plays in order**:

| Play | Runs On | What It Does |
|------|---------|--------------|
| Pre-flight checks | ALL | Verify every computer meets requirements |
| Common OS prep | ALL | Install packages, configure OS, disable swap |
| Initialize master | Masters only | Start Kubernetes control plane, install Cilium |
| Join workers | Workers only | Connect workers to the master |
| Post-install verify | Masters | Check everything is healthy, print final state |

---

### `reset.yml` — The Undo Button

**Purpose**: Completely destroy the cluster and return computers to a clean state.

**WARNING**: Irreversible. All data, pods, configs — gone.

```bash
ansible-playbook -i inventory/onprem.ini reset.yml
```

What it does, in order:
1. `kubeadm reset -f` — tears down the Kubernetes control plane and certificates
2. Removes CNI (network plugin) configuration
3. Deletes kubeconfig files
4. Removes Kubernetes package repository files
5. Uninstalls Cilium via Helm
6. Deletes Cilium's virtual network interfaces
7. Flushes all iptables firewall rules
8. Restarts containerd
9. Deletes the local kubeconfig on your computer

---

## Roles — The Job Workers

Each role is a folder under `roles/` that does ONE specific job. Every role has a `tasks/main.yml` — the actual to-do list.

### `preflight` — The Checklist

**Purpose**: Check every computer meets minimum requirements BEFORE installing anything.

If any check fails → the whole playbook stops → you see a clear error message.

| Check | Requirement | Why |
|-------|------------|-----|
| Operating System | Ubuntu 22/24, Debian 12, or RHEL 9 | Installation steps differ by OS |
| Kernel version | >= 5.10 | Cilium eBPF requires 5.10+ |
| CPU | >= 2 cores | Kubernetes hard requirement |
| RAM (master) | >= 2 GB (2048 MB) | Control plane needs memory |
| RAM (workers) | >= 1.5 GB (1536 MB) | Enough for running pods |
| Disk space | >= 20 GB free on / | Container images + logs + etcd data |
| Internet | Can reach pkgs.k8s.io, docker.com, quay.io, get.helm.sh | Downloads packages from these |
| Unique hostnames | No duplicates | Kubernetes identifies nodes by hostname |
| Unique IPs | No duplicates | Catch typos in inventory |

---

### `common` — OS Setup

**Purpose**: Prepare every computer's operating system for Kubernetes.

**Tasks in order**:

1. **Set architecture fact** — figure out if we're on x86_64 or ARM64, set variable names for later.

2. **Set hostname** — give each computer its name from inventory. Kubernetes uses hostnames as node IDs.

3. **Update /etc/hosts** — add every cluster computer to each computer's local "phone book". Allows name lookup even without DNS.

4. **Set timezone** — Asia/Kolkata. All clocks must be in sync for certificates and tokens to work.

5. **Configure SELinux** — on RedHat only. Set to "permissive" (logs but doesn't block Kubernetes actions).

6. **Full system upgrade** — update all software. Security patches + fresh foundation.

7. **Install prerequisite packages** — tools Kubernetes depends on:
   - `curl`, `wget` — download files
   - `ca-certificates` — verify HTTPS downloads
   - `socat` — used by `kubectl port-forward`
   - `conntrack` — tracks network connections (required by networking)
   - `ipset`, `ipvsadm` — network filtering and load balancing tools
   - `chrony` — time synchronization
   - `open-iscsi` — network storage connectivity
   - `nfs-common` — NFS storage mounting

8. **Configure chrony** — set up time sync with internet time servers.

9. **Disable swap** — both immediately AND permanently via /etc/fstab.
   - **Why?** Kubernetes requires swap to be OFF. With swap enabled, Kubernetes refuses to start.
   - Swap = using hard disk as fake RAM. Causes unpredictable slowdowns that break Kubernetes scheduling.

10. **Load kernel modules** — plugins for the Linux kernel:
    - `overlay` — lets containers share filesystem layers (saves disk space)
    - `br_netfilter` — lets firewall see traffic going through virtual network bridges
    - `iscsi_tcp` — network storage connectivity
    - `dm_crypt` — encrypted storage support

11. **Set sysctl parameters** — low-level kernel network settings:

| Parameter | Value | Why |
|-----------|-------|-----|
| `net.bridge.bridge-nf-call-iptables` | 1 | Makes pod traffic go through firewall rules |
| `net.ipv4.ip_forward` | 1 | Allow routing packets between network interfaces |
| `kernel.unprivileged_bpf_disabled` | 0 | Allow Cilium's eBPF programs |
| `net.core.bpf_jit_enable` | 1 | Compile eBPF to native code for speed |

12. **Increase system limits** — allow 1 million open files and processes. Kubernetes opens many simultaneously; default limits (1024) are way too low.

13. **Disable multipathd** — prevents conflict with iSCSI storage. Masked = cannot start even accidentally.

14. **Write kubelet extra args** — tell kubelet which IP to use. Important if computer has multiple network cards.

15. **Firewall management** — either disable the firewall OR open specific Kubernetes ports, depending on `disable_host_firewall` setting.

---

### `containerd` — Container Engine

**Purpose**: Install and configure containerd — the container runtime.

**What is a container runtime?**
- Kubernetes is the driver. Containerd is the engine.
- Kubernetes says "start this app". Containerd actually does it.
- Without containerd, Kubernetes can't run anything.

**Why containerd, not Docker?**
- Docker uses containerd internally. We install containerd directly (less overhead).
- Kubernetes dropped direct Docker support in v1.24. Containerd is the standard.

**Tasks in order**:

1. **Download Docker GPG key** — a security key to verify packages are authentic, not tampered with.

2. **Add Docker apt/yum repository** — tells the package manager where to download containerd from. Docker's repository has the most up-to-date version.

3. **Install containerd.io** — the actual installation. `containerd.io` = Docker's version (more current than OS built-in).

4. **Create config directories** — `/etc/containerd/` and `/etc/containerd/certs.d/` for storing config and registry certificates.

5. **Generate default config** — ask containerd to generate its own default config as a starting point.

6. **Write the config** — save the default config to `/etc/containerd/config.toml`.

7. **Enable SystemdCgroup** — critical setting. Change `SystemdCgroup = false` to `true`.
   - Why? Kubernetes, containerd, and Linux systemd must ALL use the same cgroup manager.
   - Mixing "cgroupfs" and "systemd" causes mysterious resource limit failures.

8. **Set pause image version** — pin the "pause" container to version 3.10.
   - Every Kubernetes pod has one pause container that holds the pod's network identity.
   - Must match the Kubernetes version to avoid subtle networking bugs.

9. **Set config_path** — tell containerd where to find custom registry certificate configs.

10. **Start and enable containerd** — start the service and make it start on reboot.

---

### `kubernetes` — Install k8s Tools

**Purpose**: Install the three core Kubernetes command-line tools on EVERY computer.

**The Three Tools**:

| Tool | What It Is | When Used |
|------|-----------|-----------|
| `kubelet` | The Kubernetes AGENT running on every computer. Receives instructions from master, starts/stops containers. Always running as a system service. | Always — must run 24/7 on every node |
| `kubeadm` | The SETUP TOOL. Used to initialize the cluster (`kubeadm init`) and join nodes (`kubeadm join`). | Only during cluster setup |
| `kubectl` | The CONTROL TOOL. Command-line to talk to Kubernetes: `kubectl get pods`, `kubectl apply`, etc. | Whenever you manage the cluster |

**Why we lock (pin) the versions**:
- `apt upgrade` or `yum update` could accidentally upgrade kubelet/kubeadm/kubectl.
- Kubernetes version upgrades are a multi-step process — you can't just bump versions.
- `hold` (Debian) or `versionlock` (RedHat) prevents accidental upgrades.

---

### `master` — Start the Boss Computer

**Purpose**: Initialize the Kubernetes control plane on the master. The most critical role.

**Tasks in order**:

1. **Check if already initialized** — look for `/etc/kubernetes/admin.conf`. If it exists, cluster was already initialized → skip `kubeadm init`. Makes playbook safe to re-run.

2. **Detect API server IP** — figure out which IP the API server will listen on. Auto-detects if not set in config.

3. **Get AWS public IP** (AWS only) — fetch the EC2 instance's public IP from the metadata service. Needed to connect to kubectl from outside AWS.

4. **Build certSANs list** — list of IPs/names to put in the API server's TLS certificate. If you connect from an IP not in this list, you get an SSL error.

5. **Write kubeadm init config** — fill in the `kubeadm-init.yaml.j2` template and write it to `/etc/kubernetes/kubeadm-init.yaml`.

6. **Run kubeadm init** — THE key moment. This starts the entire Kubernetes control plane:
   - `etcd` — the database storing all cluster state
   - `kube-apiserver` — the API server (all kubectl commands go here)
   - `kube-scheduler` — decides which worker runs each pod
   - `kube-controller-manager` — maintains desired vs actual state
   - Takes 2-5 minutes. Only runs if cluster not already initialized.

7. **Set up kubeconfig** — copy `/etc/kubernetes/admin.conf` to `~/.kube/config` for both root and ansible user. Lets you run `kubectl` commands from the master.

8. **Install Helm** — download, verify checksum, extract, install the Helm binary to `/usr/local/bin/helm`. Helm is the package manager for Kubernetes apps.

9. **Install Cilium** — run `helm install` to deploy Cilium:
   - Downloads Cilium from quay.io
   - Deploys it into the `kube-system` namespace
   - Enables kube-proxy replacement (faster eBPF networking)
   - Configures IP address management for pods

10. **Wait for control plane** — retry until at least 4 system pods are Running. Prevents proceeding before the cluster brain is healthy.

11. **Generate join token** — create a token (temporary password) that workers use to join. Saves the full `kubeadm join ...` command as a variable.

12. **Fetch kubeconfig** — copy the kubeconfig from the master to your local computer. Now you can run `kubectl` from your laptop.

13. **Patch kubeconfig** (AWS only) — replace the internal IP with the public IP so kubectl works from outside AWS.

---

### `worker` — Connect Helper Computers

**Purpose**: Run the join command on each worker so it becomes part of the cluster.

**Tasks in order**:

1. **Verify join command exists** — safety check: make sure the master role ran successfully and gave us a join command. Clear error message if it didn't.

2. **Check if already joined** — ask the master "is this worker already registered?" by running `kubectl get node worker-1` on the master. Skip join if yes.

3. **Clean up stale state** — if a previous join attempt failed halfway, delete leftover files that would prevent a new attempt:
   - `/etc/kubernetes/kubelet.conf`
   - `/etc/kubernetes/pki/`
   - `/var/lib/kubelet/config.yaml`

4. **Run join command** — execute the `kubeadm join ...` command saved from the master. This:
   - Downloads cluster info from the master
   - Generates TLS certificates for this worker
   - Registers the worker with the master's API server
   - Configures kubelet to talk to the master

5. **Ensure kubelet is running** — confirm kubelet started and will start on reboot.

6. **Label as worker** — add the label `node-role.kubernetes.io/worker=worker` so kubectl shows "worker" in the ROLES column instead of `<none>`.

---

## Templates

Templates are files with `{{ variables }}` that Ansible fills in before using.
File extension `.j2` = Jinja2 (the template language Ansible uses).

### `kubeadm-init.yaml.j2`

Written to `/etc/kubernetes/kubeadm-init.yaml` on the master. Used by `kubeadm init`.

Three sections:

**Section 1 — InitConfiguration** (local to this specific master node):
- `advertiseAddress` — which IP the API server listens on
- `criSocket` — path to containerd's socket file (how kubeadm talks to containerd)
- `imagePullPolicy: IfNotPresent` — only download container images if not already cached
- `skipPhases: [addon/kube-proxy]` — don't install kube-proxy (Cilium replaces it)

**Section 2 — ClusterConfiguration** (global cluster settings):
- `kubernetesVersion` — which control plane images to pull
- `clusterName: kubernetes` — just a label
- `dnsDomain: cluster.local` — internal DNS suffix (e.g. `myapp.default.svc.cluster.local`)
- `podSubnet` — IP range for pods (from group_vars)
- `serviceSubnet` — IP range for services (from group_vars)
- `certSANs` — list of IPs/names in the API server's TLS certificate

**Section 3 — KubeletConfiguration** (kubelet settings on the master):
- `cgroupDriver: systemd` — use systemd cgroup management (must match containerd config)

### `chrony.conf.j2`

Written to `/etc/chrony.conf` on every computer.

```
server 0.pool.ntp.org iburst
server 1.pool.ntp.org iburst
```
Tells chrony which time servers to sync with. `iburst` = sync fast on startup.

```
driftfile /var/lib/chrony/drift
```
Track how fast/slow the hardware clock is, so chrony can compensate.

```
makestep 1.0 3
```
If the clock is off by more than 1 second during the first 3 syncs after boot, jump the clock instantly to the correct time instead of gradually adjusting.

```
rtcsync
```
Keep the hardware clock (CMOS battery clock) updated so reboots don't cause clock jumps.

---

## Where to Start — Action Steps

Do these in order:

### Step 1 — Prepare your computers

- At least 3 Linux computers (VMs are fine)
- Ubuntu 22.04, Debian 12, or Rocky Linux 9 recommended
- Each computer: 2+ CPUs, 2+ GB RAM, 20+ GB disk
- SSH access from your laptop to each computer

### Step 2 — Edit the inventory file

Open `inventory/onprem.ini` and replace the example IPs with your actual ones:

```ini
[masters]
master-1 ansible_host=YOUR_MASTER_IP ansible_user=YOUR_USERNAME

[workers]
worker-1 ansible_host=YOUR_WORKER1_IP ansible_user=YOUR_USERNAME
worker-2 ansible_host=YOUR_WORKER2_IP ansible_user=YOUR_USERNAME
```

### Step 3 — Review settings

Open `group_vars/all.yml` and check:
- `cloud_provider: onprem` (or `aws` if on AWS)
- `pod_network_cidr` doesn't overlap with your real network
- `disable_host_firewall: true` (change to `false` if you want Ansible to manage firewall)

### Step 4 — Install extra Ansible tools

```bash
ansible-galaxy collection install -r requirements.yml
```

Run this once. Downloads `ansible.posix` and `community.general` collections.

### Step 5 — Test SSH connectivity

```bash
ansible k8s_cluster -i inventory/onprem.ini -m ping
```

Should see `pong` from all computers. If not, fix SSH access first.

### Step 6 — Run the playbook

```bash
ansible-playbook -i inventory/onprem.ini site.yml
```

Takes 15-30 minutes. Watch the output — each task prints what it's doing.

### Step 7 — Use your cluster

```bash
export KUBECONFIG=$(pwd)/kubeconfig
kubectl get nodes
```

Should show all your computers with status `Ready`.

---

## The Full Flow When You Run It

```
ansible-playbook -i inventory/onprem.ini site.yml
        │
        ▼
┌─────────────────────────────────────────────────────┐
│  PLAY 1: preflight (all computers)                  │
│  Check OS, kernel, CPU, RAM, disk, internet, IPs    │
│  → FAIL FAST if anything is wrong                   │
└─────────────────────────┬───────────────────────────┘
                          │ all checks passed
                          ▼
┌─────────────────────────────────────────────────────┐
│  PLAY 2: common + containerd + kubernetes (all)     │
│  Set hostname, timezone, install packages           │
│  Disable swap, load kernel modules, set sysctl      │
│  Install containerd and configure it                │
│  Install kubelet, kubeadm, kubectl                  │
└─────────────────────────┬───────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────┐
│  PLAY 3: master (master computers only)             │
│  Run kubeadm init                                   │
│  Set up kubeconfig                                  │
│  Install Helm                                       │
│  Install Cilium (networking)                        │
│  Wait for control plane to be healthy               │
│  Generate worker join token                         │
│  Copy kubeconfig to your laptop                     │
└─────────────────────────┬───────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────┐
│  PLAY 4: worker (worker computers only)             │
│  Run kubeadm join command                           │
│  Label node as "worker"                             │
└─────────────────────────┬───────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────┐
│  PLAY 5: verify (from master)                       │
│  Wait for all nodes = Ready                         │
│  Wait for Cilium pods = Running                     │
│  Wait for CoreDNS pods = Running                    │
│  Print final cluster state                          │
│  Print kubeconfig location                          │
└─────────────────────────────────────────────────────┘
```

---

## Key Words Glossary

| Word | Plain English Explanation |
|------|--------------------------|
| **Kubernetes** | A system for running and managing containerized apps across multiple computers. |
| **Ansible** | A tool that automates configuration of computers via SSH. No agent needed on computers. |
| **Playbook** | An Ansible script file (`.yml`) that lists tasks to run on computers. |
| **Role** | A reusable folder of tasks for one specific job (like "install containerd"). |
| **Task** | One single step in Ansible (like "install package X" or "start service Y"). |
| **Inventory** | The list of computers Ansible manages, with their IPs and usernames. |
| **Variable** | A named value you can reuse. Like `kubernetes_version: "1.36.1"`. |
| **Fact** | Information Ansible automatically collects about a computer (OS, RAM, IP, etc.). |
| **Tag** | A label on a task/play so you can selectively run just that part with `--tags`. |
| **Module** | A built-in Ansible tool for a specific action (like `apt`, `service`, `copy`). |
| **Handler** | A task that only runs when "notified" (e.g. restart service only when config changed). |
| **Template** | A file with `{{ variables }}` that Ansible fills in before deploying. |
| **Master / Control Plane** | The boss computer running the Kubernetes brain (API server, scheduler, etcd). |
| **Worker / Node** | A computer that runs your actual applications (pods). |
| **Pod** | The smallest deployable unit in Kubernetes — one or more containers sharing a network. |
| **Container** | An isolated process with its own filesystem and network (like a mini-VM, much lighter). |
| **containerd** | The container runtime — the engine that actually starts and stops containers. |
| **kubelet** | The Kubernetes agent running on every computer, receiving orders from the master. |
| **kubeadm** | The tool used to set up and initialize a Kubernetes cluster. |
| **kubectl** | The command-line tool to control Kubernetes (like a remote control). |
| **Cilium** | The networking plugin for Kubernetes — gives every pod an IP and connects them. Uses eBPF. |
| **eBPF** | A Linux technology allowing safe programs to run inside the kernel for very fast networking. |
| **Helm** | A package manager for Kubernetes — installs complex apps with one command. |
| **etcd** | A key-value database where Kubernetes stores ALL cluster state. |
| **CNI** | Container Network Interface — the plugin that gives pods IP addresses. |
| **kubeconfig** | A file with credentials and server address for kubectl to connect to Kubernetes. |
| **CertSAN** | Certificate Subject Alternative Name — extra IPs/hostnames in a TLS certificate. |
| **Namespace** | A virtual "folder" inside Kubernetes that groups related resources. |
| **Swap** | Using hard disk as fake RAM. Must be OFF for Kubernetes. |
| **cgroup** | Linux mechanism to limit CPU/memory usage per process. Kubernetes uses this to limit pods. |
| **sysctl** | Command to read/set Linux kernel parameters at runtime without rebooting. |
| **iptables** | Linux firewall rules. Kubernetes and Cilium add many rules here. |
| **NTP** | Network Time Protocol — syncs computer clocks with internet time servers. |
| **GPG key** | A cryptographic key used to verify that a downloaded package is authentic. |
| **CIDR** | A way to write IP address ranges. `10.244.0.0/16` = 10.244.0.0 to 10.244.255.255. |
| **IMDSv2** | AWS Instance Metadata Service v2 — a special URL inside EC2 that returns instance info. |
| **Idempotent** | Safe to run multiple times — running it again produces the same result, no duplicate actions. |
