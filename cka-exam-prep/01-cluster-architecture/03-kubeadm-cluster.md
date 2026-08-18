# 1.3 — Create and Manage Kubernetes Clusters Using kubeadm

> **Objective:** Create and manage Kubernetes clusters using kubeadm.
> **Exam frequency:** High. Cluster creation/join/reset is a frequent task.

## 🎯 Why this matters

`kubeadm` is the tool the exam uses to provision real clusters. You must be able to init, join, reset, and tweak with confidence.

## 🧠 What kubeadm does

`kubeadm init` performs (in order):
1. **Preflight checks** — swap, ports, kernel, etc.
2. Generates **PKI** (certificates) under `/etc/kubernetes/pki/`
3. Writes **kubeconfig** files: `admin.conf`, `kubelet.conf`, `controller-manager.conf`, `scheduler.conf`
4. Writes **static pod manifests** for the control plane to `/etc/kubernetes/manifests/`
5. **Starts kubelet** — kubelet sees the static manifests and brings up the control plane pods
6. Bootstraps etcd, applies cluster-info ConfigMap
7. Installs the kube-proxy DaemonSet and CoreDNS
8. Prints the **join command** for workers

## 🛠️ Core commands

### Initialize the control plane

```bash
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=<ip>
```

Common flags:
- `--pod-network-cidr` — must match your CNI's expected range (Calico default `192.168.0.0/16`, Flannel `10.244.0.0/16`)
- `--apiserver-advertise-address` — explicit IP if node has multiple
- `--control-plane-endpoint` — DNS/LB for HA setups
- `--kubernetes-version v1.34.0` — pin a version
- `--upload-certs` — for HA, distributes certs to other CP nodes
- `--config <file>` — full config-file mode (preferred for production)

### Set up kubectl access

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### Print the join command (re-generate if you missed it)

```bash
kubeadm token create --print-join-command
```

Output looks like:
```
kubeadm join 192.168.1.10:6443 --token abc.123... --discovery-token-ca-cert-hash sha256:def456...
```

### Join a worker node

```bash
sudo kubeadm join <cp-ip>:6443 --token <tok> --discovery-token-ca-cert-hash sha256:<hash>
```

### Join a second control plane (HA)

```bash
sudo kubeadm join <cp-ip>:6443 \
  --token <tok> --discovery-token-ca-cert-hash sha256:<hash> \
  --control-plane --certificate-key <key>
```

The `--certificate-key` comes from `kubeadm init --upload-certs` output, or:
```bash
sudo kubeadm init phase upload-certs --upload-certs
```

### Reset (start over)

```bash
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d /etc/kubernetes
sudo ipvsadm --clear 2>/dev/null || true
sudo systemctl restart containerd
```

### Where things live

| Item | Path |
| --- | --- |
| Static pod manifests | `/etc/kubernetes/manifests/` |
| kubeconfig files | `/etc/kubernetes/{admin,controller-manager,scheduler,kubelet}.conf` |
| PKI (certs, keys) | `/etc/kubernetes/pki/` |
| kubelet config | `/var/lib/kubelet/config.yaml` |
| kubelet flags | `/var/lib/kubelet/kubeadm-flags.env` |
| etcd data | `/var/lib/etcd/` |
| Container runtime logs | `crictl logs <id>`, `journalctl -u containerd` |
| kubelet logs | `journalctl -u kubelet -f` |

## 📄 Using a config file (production style)

Generate a default config:
```bash
kubeadm config print init-defaults > kubeadm-config.yaml
```

Edit it:
```yaml
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: 192.168.1.10
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///var/run/containerd/containerd.sock
  name: control-plane-1
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: v1.34.0
controlPlaneEndpoint: "cluster-endpoint:6443"
networking:
  podSubnet: "10.244.0.0/16"
  serviceSubnet: "10.96.0.0/12"
etcd:
  local:
    dataDir: /var/lib/etcd
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
```

Init with it:
```bash
sudo kubeadm init --config kubeadm-config.yaml
```

## 🔍 Inspecting an existing cluster

```bash
# kubeadm config currently in use
kubectl get cm kubeadm-config -n kube-system -o yaml

# What versions are installed?
kubeadm version
kubelet --version
kubectl version --short

# What components are running?
kubectl get pods -n kube-system

# Static pod definitions (live config of control plane)
ls /etc/kubernetes/manifests/
cat /etc/kubernetes/manifests/kube-apiserver.yaml
```

## 🏋️ Exam-style exercises

### Exercise 1
On a prepared VM, initialize a Kubernetes cluster using kubeadm. Use pod CIDR `10.244.0.0/16`. Set up kubectl access for the non-root user. Print the join command.

<details><summary>Solution</summary>

```bash
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

kubectl get nodes  # control plane should appear (NotReady until CNI)

kubeadm token create --print-join-command
```
</details>

### Exercise 2
Join a worker node to an existing cluster. You don't have the original join command.

<details><summary>Solution</summary>

On control plane:
```bash
kubeadm token create --print-join-command
# Copy the output
```

On worker:
```bash
sudo <paste the join command>
```

Verify on CP: `kubectl get nodes` (new node should appear).
</details>

### Exercise 3
The token printed at init time has expired (default TTL 24h). Generate a new one with a 2h TTL.

<details><summary>Solution</summary>

```bash
kubeadm token create --ttl 2h --print-join-command
# Or just:
kubeadm token create --ttl 2h
kubeadm token list  # see all tokens

# If you need the CA hash separately:
openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | \
  openssl rsa -pubin -outform der 2>/dev/null | \
  openssl dgst -sha256 -hex | sed 's/^.* //'
```
</details>

### Exercise 4
Re-initialize the cluster after a failed install.

<details><summary>Solution</summary>

```bash
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d
sudo rm -rf $HOME/.kube/config
sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X
sudo systemctl restart containerd
sudo kubeadm init <flags>
```
</details>

### Exercise 5
Add a label `node-role.kubernetes.io/worker=` to a newly joined worker so it appears with the `worker` role in `kubectl get nodes`.

<details><summary>Solution</summary>

```bash
kubectl label node worker-1 node-role.kubernetes.io/worker=
kubectl get nodes
```
</details>

## ⚠️ Common pitfalls

- **Token expired** (24h default). Always regenerate before joining new nodes: `kubeadm token create --print-join-command`.
- **Pod CIDR conflict with CNI default**. Calico expects `192.168.0.0/16` by default; if you set `--pod-network-cidr=10.244.0.0/16` you must configure Calico to use that.
- **Forgot to install CNI** → nodes NotReady forever.
- **Skipped `kubeadm reset` before re-init** → port 10250 already in use, etcd data dir conflicts.
- **Time skew** between nodes ≥ 5 min → TLS handshakes fail. Run NTP/`chrony` on every node.

## 📚 Doc bookmarks

- [Creating a cluster with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)
- [kubeadm reference](https://kubernetes.io/docs/reference/setup-tools/kubeadm/)
- [kubeadm config](https://kubernetes.io/docs/reference/config-api/kubeadm-config.v1beta4/)
