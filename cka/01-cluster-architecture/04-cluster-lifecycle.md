# 1.4 — Manage the Lifecycle of Kubernetes Clusters

> **Objective:** Manage the lifecycle of Kubernetes clusters.
> **Exam frequency:** Very high. The "upgrade with kubeadm" task is a classic, worth ~7%.

## 🎯 Why this matters

Production clusters need quarterly upgrades, node maintenance, and certificate rotation. The exam tests all three.

## 🧠 Lifecycle activities

1. **Upgrade** — minor version bumps (1.33 → 1.34) via `kubeadm upgrade`
2. **Node maintenance** — `cordon`, `drain`, `uncordon`
3. **Certificate management** — renewal of internal PKI
4. **Node addition/removal**
5. **etcd backup/restore** (see [05-ha-control-plane.md](./05-ha-control-plane.md))

## 🔼 Upgrade with kubeadm (the exam task)

**Critical:** upgrades must be done **one minor version at a time** (1.33 → 1.34, not 1.32 → 1.34).

### Step-by-step (memorize)

#### On the **control plane** node:

```bash
# 1. Find the latest patch of the target minor version
sudo apt update
sudo apt-cache madison kubeadm | grep 1.34
# pick e.g. 1.34.2-1.1

# 2. Unhold and upgrade kubeadm
sudo apt-mark unhold kubeadm
sudo apt-get install -y kubeadm=1.34.2-1.1
sudo apt-mark hold kubeadm

# 3. Verify
sudo kubeadm version

# 4. Plan the upgrade (shows what will change)
sudo kubeadm upgrade plan

# 5. Apply
sudo kubeadm upgrade apply v1.34.2

# 6. Drain the CP node (so kubelet upgrade is safe)
kubectl drain <cp-node> --ignore-daemonsets

# 7. Upgrade kubelet + kubectl
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=1.34.2-1.1 kubectl=1.34.2-1.1
sudo apt-mark hold kubelet kubectl

# 8. Restart kubelet
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# 9. Uncordon
kubectl uncordon <cp-node>
```

#### On each **worker** node:

```bash
# On the control plane:
kubectl drain <worker> --ignore-daemonsets --delete-emptydir-data

# On the worker:
sudo apt-mark unhold kubeadm
sudo apt-get install -y kubeadm=1.34.2-1.1
sudo apt-mark hold kubeadm

sudo kubeadm upgrade node     # NOTE: 'upgrade node', not 'upgrade apply'

sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=1.34.2-1.1 kubectl=1.34.2-1.1
sudo apt-mark hold kubelet kubectl

sudo systemctl daemon-reload
sudo systemctl restart kubelet

# Back on the control plane:
kubectl uncordon <worker>
```

### Verify

```bash
kubectl get nodes  # all nodes should show v1.34.2
kubectl get pods -A  # control plane pods running, no crashes
```

## 🚧 Node maintenance — cordon, drain, uncordon

### `cordon` — stop new pods from being scheduled here

```bash
kubectl cordon <node>
# Node is marked SchedulingDisabled. Existing pods keep running.
```

### `drain` — gracefully evict workloads

```bash
kubectl drain <node> \
  --ignore-daemonsets \      # DaemonSet pods can't be evicted by design
  --delete-emptydir-data \   # acknowledge that emptyDir data will be lost
  --force                    # for naked pods (not managed by a controller)
```

Drain implicitly cordons first. Use it before:
- Rebooting a node
- Upgrading kubelet
- Decommissioning hardware
- Major OS patching

### `uncordon` — put it back

```bash
kubectl uncordon <node>
```

## 🗑️ Removing a node

```bash
# On control plane:
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
kubectl delete node <node>

# On the leaving node:
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d $HOME/.kube
sudo iptables -F && sudo iptables -t nat -F
```

## 🔐 Certificate management

`kubeadm` generates internal certs that **expire after 1 year**.

```bash
# Check expiration
sudo kubeadm certs check-expiration

# Renew all certs
sudo kubeadm certs renew all

# Renew a specific one
sudo kubeadm certs renew apiserver

# Restart static control plane pods to pick up new certs
sudo crictl ps | grep -E 'apiserver|controller-manager|scheduler|etcd'
# Move static manifests out and back in (kubelet auto-restarts the pods):
sudo mv /etc/kubernetes/manifests /tmp/manifests-backup
sleep 30
sudo mv /tmp/manifests-backup /etc/kubernetes/manifests
```

After renew, regenerate `admin.conf`:
```bash
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
```

## 🏋️ Exam-style exercises

### Exercise 1
Upgrade the control plane node from v1.33.x to v1.34.x. Then upgrade the worker node.

<details><summary>Solution</summary>
Follow the step-by-step above exactly. Verify with `kubectl get nodes`.
</details>

### Exercise 2
A node `worker-2` needs OS patches. Drain it, run a fake patch (`sleep 10`), then return it to service.

<details><summary>Solution</summary>

```bash
kubectl drain worker-2 --ignore-daemonsets --delete-emptydir-data
# (on worker-2 — but for exam, just simulate)
sleep 10
kubectl uncordon worker-2
kubectl get nodes  # should be Ready, no SchedulingDisabled
```
</details>

### Exercise 3
A node has DaemonSet pods that won't allow `drain`. Drain anyway and verify only DaemonSet pods remain.

<details><summary>Solution</summary>

```bash
kubectl drain <node> --ignore-daemonsets

# Optionally also drain with these flags as needed:
# --delete-emptydir-data   for pods using emptyDir
# --force                  for naked pods

kubectl get pods --all-namespaces -o wide | grep <node>
# Should only show DaemonSet pods (e.g., kube-proxy, calico-node)
```
</details>

### Exercise 4
Check when the apiserver certificate expires and renew it.

<details><summary>Solution</summary>

```bash
sudo kubeadm certs check-expiration

# Renew just apiserver
sudo kubeadm certs renew apiserver

# Restart kube-apiserver static pod
sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/
sleep 20
sudo mv /tmp/kube-apiserver.yaml /etc/kubernetes/manifests/

# Wait and verify
sleep 30
sudo kubeadm certs check-expiration
```
</details>

## ⚠️ Common pitfalls

- **Wrong order of operations.** `kubeadm upgrade apply` BEFORE `apt install kubelet=...`. Otherwise kubelet won't talk to upgraded apiserver.
- **`kubeadm upgrade apply` vs `kubeadm upgrade node`.** First is CP only. Second is for workers and additional CP nodes.
- **Skipping `kubectl drain`** — pods get killed ungracefully when kubelet restarts.
- **Trying to skip minor versions.** Not supported. Upgrade one at a time.
- **Forgetting `apt-mark hold` after** — next `apt upgrade` will randomly bump kubelet.
- **Forgetting `--ignore-daemonsets` on drain** — drain fails immediately.

## 📚 Doc bookmarks

- [Upgrading kubeadm clusters](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/) — **bookmark this, the exam mirrors it**
- [Safely Drain a Node](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/)
- [Certificate Management with kubeadm](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/)

## 🔁 Speed drill (do twice in your lab)

End-to-end: upgrade your 2-node kubeadm lab from v1.33 → v1.34. Time yourself. **Target: < 25 minutes.**
