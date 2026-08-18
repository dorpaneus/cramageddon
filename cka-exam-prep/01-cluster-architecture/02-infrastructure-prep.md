# 1.2 — Prepare Underlying Infrastructure for Installing a Kubernetes Cluster

> **Objective:** Prepare underlying infrastructure for installing a Kubernetes cluster.
> **Exam frequency:** Low as standalone — but every install task assumes you know this.

## 🎯 Why this matters

`kubeadm init` will fail or hang silently if the host isn't prepared. This is the boring-but-deadly checklist.

## ✅ Pre-install checklist (memorize this)

| Requirement | Why | Command |
| --- | --- | --- |
| 2+ CPU, 2+ GB RAM | kubelet/control plane need it | `lscpu`, `free -h` |
| Unique hostname per node | Cluster identifies nodes by hostname | `hostnamectl` |
| Unique MAC and product_uuid | K8s uses these as fallback IDs | `ip link`, `cat /sys/class/dmi/id/product_uuid` |
| **Swap disabled** | kubelet refuses to start with swap on | `swapoff -a` + edit `/etc/fstab` |
| Kernel modules: `overlay`, `br_netfilter` | Container runtime + networking | `lsmod \| grep <mod>` |
| `net.bridge.bridge-nf-call-iptables=1` | Pod-to-pod traffic via iptables | `sysctl -a \| grep bridge-nf` |
| `net.ipv4.ip_forward=1` | Routing between pods | `sysctl net.ipv4.ip_forward` |
| Container runtime installed (containerd) | kubelet talks to it via CRI | `systemctl status containerd` |
| Firewall ports open | See port table below | `firewall-cmd --list-ports` |
| `kubeadm`, `kubelet`, `kubectl` installed | The tools | `kubeadm version`, `kubelet --version` |

## 🔌 Required ports

### Control plane

| Port | Protocol | Component | Source |
| --- | --- | --- | --- |
| 6443 | TCP | kube-apiserver | All |
| 2379–2380 | TCP | etcd client + peer | kube-apiserver, etcd |
| 10250 | TCP | kubelet API | Self, control plane |
| 10257 | TCP | kube-controller-manager | Self |
| 10259 | TCP | kube-scheduler | Self |

### Worker nodes

| Port | Protocol | Component |
| --- | --- | --- |
| 10250 | TCP | kubelet API |
| 10256 | TCP | kube-proxy |
| 30000–32767 | TCP | NodePort services |

## 🛠️ The exact pre-install script

```bash
#!/bin/bash
set -euo pipefail

# 1. Disable swap (permanent)
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# 2. Kernel modules
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

# 3. Sysctl params
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system

# 4. Install containerd
sudo apt-get update
sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null

# 5. Configure containerd to use systemd cgroup driver (MUST match kubelet)
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# 6. Install kubeadm, kubelet, kubectl
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# 7. Enable kubelet (won't start until kubeadm init runs)
sudo systemctl enable kubelet
```

## 🐳 cgroup driver — the single most common failure

**Problem:** kubelet refuses to start, or pods are in `CrashLoopBackOff` everywhere.
**Cause:** kubelet's cgroup driver doesn't match containerd's.
**Fix:** Both must be `systemd`. Check:

```bash
# containerd
grep SystemdCgroup /etc/containerd/config.toml
# should be: SystemdCgroup = true

# kubelet (after kubeadm init)
cat /var/lib/kubelet/config.yaml | grep cgroupDriver
# should be: cgroupDriver: systemd
```

## 🏋️ Exam-style exercises

### Exercise 1
A new VM has been provisioned. Make it ready to run `kubeadm init`. Use containerd as the runtime.

<details><summary>Solution</summary>
Run the pre-install script above. Verify with:

```bash
swapon --show          # empty
lsmod | grep br_netfilter
sysctl net.ipv4.ip_forward
systemctl is-active containerd  # active
kubeadm version
```
</details>

### Exercise 2
On a prepared node, `kubeadm init` fails with `[ERROR Swap]: running with swap on is not supported`. Fix it.

<details><summary>Solution</summary>

```bash
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
sudo kubeadm reset -f
sudo kubeadm init
```
</details>

### Exercise 3
After `kubeadm init`, all pods are stuck in `Pending` and the node is `NotReady`. What did you forget?

<details><summary>Solution</summary>

The CNI plugin. `kubeadm` doesn't install one. Install Calico, Flannel, or Cilium:

```bash
# Calico (simplest)
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/custom-resources.yaml
```

Then `kubectl get nodes` should show `Ready` within a minute.
</details>

## ⚠️ Common pitfalls

- **`apt update` failing on K8s repo** — you used an old `pkgs.k8s.io` URL (the apt.kubernetes.io repo was retired in 2023). Use `pkgs.k8s.io/core:/stable:/v1.34/deb/`.
- **MAC collision** between cloned VMs — clone with "generate new MAC" or `ip link set <iface> address <new-mac>`.
- **Firewall blocking 6443** between worker and control plane — worker join hangs at `Establishing TLS bootstrap`.
- **Forgetting to set systemd cgroup driver in containerd** — kubelet logs show `failed to start ContainerManager`.

## 📚 Doc bookmarks

- [Installing kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/) — has the canonical pre-flight steps
- [Container runtimes](https://kubernetes.io/docs/setup/production-environment/container-runtimes/) — containerd cgroup driver config
- [Ports and Protocols](https://kubernetes.io/docs/reference/networking/ports-and-protocols/) — port reference
