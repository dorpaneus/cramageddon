# Pod Scheduling: Requests, Limits, Affinity, Taints, Topology Spread

> **Objective (CNCF):** Use Kubernetes primitives to implement common deployment strategies. Understand the role of resource requests/limits, node affinity, taints and tolerations, and topology spread constraints in pod scheduling.
> **Domain:** Workloads & Scheduling (15%) — **Exam frequency:** ⭐⭐⭐

---

## Why this matters

The scheduler is the most testable controller. Tasks like *"Schedule pod X only on nodes with label disk=ssd"* or *"Make sure pods spread across 3 zones"* are bread-and-butter exam material.

---

## How the scheduler decides

```
   Pod created (unscheduled)
            │
            ▼
   ┌─────────────────────┐
   │ FILTER (predicates) │  Which nodes CAN this pod fit on?
   │ - resource requests │      → node has enough CPU/mem
   │ - nodeSelector      │      → labels match
   │ - taints            │      → pod tolerates them
   │ - affinity rules    │      → required rules satisfied
   │ - PV node affinity  │
   └─────────┬───────────┘
             ▼
   ┌─────────────────────┐
   │ SCORE (priorities)  │  Of those, which is BEST?
   │ - resource balance  │
   │ - preferred affinity│
   │ - topology spread   │
   └─────────┬───────────┘
             ▼
       Pick highest score → bind pod to node
```

If filter eliminates everything: pod stays `Pending`. `kubectl describe pod` Events show why.

---

## Requests vs Limits

```yaml
resources:
  requests:                 # SCHEDULER uses this. "Reserve me this much."
    cpu: 100m               # 100 millicores = 0.1 CPU
    memory: 128Mi
  limits:                   # KUBELET enforces this. "Don't exceed."
    cpu: 500m
    memory: 256Mi
```

- **Requests** affect **scheduling**. Sum of requests on a node ≤ allocatable.
- **Limits** affect **runtime**. CPU over limit = throttled. Memory over limit = **OOMKilled**.
- No request specified → scheduler treats as 0; pod can land anywhere → may starve.
- No limit specified → pod can use all node resources; noisy neighbor.

### QoS classes (derived from requests/limits)

| Class | When | Eviction order |
|---|---|---|
| **Guaranteed** | requests == limits for **all** containers (cpu + mem) | Last to be evicted |
| **Burstable** | At least one container has requests < limits | Middle |
| **BestEffort** | No requests or limits anywhere | First to be evicted under pressure |

---

## nodeSelector — the simplest pin

```bash
kubectl label node node-1 disk=ssd
```

```yaml
spec:
  nodeSelector:
    disk: ssd
```

Hard requirement. No match → pod stays Pending.

---

## Node affinity — nodeSelector with grammar

```yaml
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:      # hard
        nodeSelectorTerms:
        - matchExpressions:
          - key: disk
            operator: In
            values: [ssd, nvme]
      preferredDuringSchedulingIgnoredDuringExecution:     # soft
      - weight: 50
        preference:
          matchExpressions:
          - key: zone
            operator: In
            values: [us-east-1a]
```

**`IgnoredDuringExecution`** means: if labels change after scheduling, the pod stays put. There's no "RequiredDuringExecution" yet.

Operators: `In`, `NotIn`, `Exists`, `DoesNotExist`, `Gt`, `Lt`.

---

## Pod affinity / anti-affinity

Place pods near or away from other pods (not nodes).

```yaml
spec:
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels: { app: web }
        topologyKey: kubernetes.io/hostname     # one per node
```

**`topologyKey`** defines the "blast radius":
- `kubernetes.io/hostname` → one per node
- `topology.kubernetes.io/zone` → one per zone

Common pattern: spread web pods one per node for HA.

---

## Taints and tolerations

**Taints repel.** Set on **nodes**:

```bash
kubectl taint nodes node-1 dedicated=db:NoSchedule
# Format: key=value:effect
```

Effects:
| Effect | Behavior |
|---|---|
| `NoSchedule` | New pods without toleration won't be scheduled here |
| `PreferNoSchedule` | Soft version |
| `NoExecute` | Plus: evict already-running pods that don't tolerate it |

**Tolerations allow.** Set on **pods**:

```yaml
spec:
  tolerations:
  - key: dedicated
    operator: Equal
    value: db
    effect: NoSchedule
```

Or tolerate all values of a key:
```yaml
- key: dedicated
  operator: Exists
  effect: NoSchedule
```

Or tolerate everything (DaemonSets often do this):
```yaml
- operator: Exists
```

**Remove a taint:**
```bash
kubectl taint nodes node-1 dedicated=db:NoSchedule-      # trailing dash deletes
```

### Control-plane taint

Control plane nodes have:
```
node-role.kubernetes.io/control-plane:NoSchedule
```
That's why workloads don't land there by default.

---

## Topology Spread Constraints (NEW emphasis in 2025 refresh)

Spread pods evenly across a topology (zones, nodes, racks).

```yaml
spec:
  topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule          # OR ScheduleAnyway
    labelSelector:
      matchLabels: { app: web }
  containers:
  - { name: web, image: nginx }
```

- **maxSkew**: max difference in pod count between any two topology domains. `1` = nearly even.
- **whenUnsatisfiable**: `DoNotSchedule` (hard) or `ScheduleAnyway` (soft, scoring only).
- **labelSelector**: which pods count.

**Why prefer over podAntiAffinity?** More flexible, lower scheduler cost, supports skew tolerance.

---

## Cordon, drain, uncordon

| Command | What it does |
|---|---|
| `kubectl cordon node-1` | Marks unschedulable; existing pods stay. Adds `node.kubernetes.io/unschedulable:NoSchedule` taint. |
| `kubectl drain node-1` | Cordons **and** evicts pods (respecting PDBs). |
| `kubectl uncordon node-1` | Reverses cordon. |

```bash
# Standard drain for maintenance:
kubectl drain node-1 --ignore-daemonsets --delete-emptydir-data
# Then patch/upgrade/reboot...
kubectl uncordon node-1
```

`--ignore-daemonsets` because DaemonSet pods can't be moved. `--delete-emptydir-data` because emptyDir data is local and will be lost — drain requires you to acknowledge it.

---

## Static pods

Pods managed directly by kubelet from a directory (not the API server).

```bash
# Default location (kubeadm clusters):
ls /etc/kubernetes/manifests/
# kube-apiserver.yaml  kube-controller-manager.yaml  kube-scheduler.yaml  etcd.yaml
```

Drop a pod YAML in `/etc/kubernetes/manifests/` and kubelet starts it. Remove the file → kubelet stops it.

```bash
# Find which kubelet directory:
ps -ef | grep kubelet
# Look for --pod-manifest-path=... or check /var/lib/kubelet/config.yaml for "staticPodPath"
```

A "mirror pod" appears in the API for visibility (`kubectl get pods -n kube-system`).

---

## Exercises

### 1. Pin a pod to SSD nodes

> Schedule a new pod `cache` (image redis) only on nodes labeled `disk=ssd`.

<details><summary>Solution</summary>

```bash
kubectl label node node-2 disk=ssd
kubectl run cache --image=redis $do --overrides='{"spec":{"nodeSelector":{"disk":"ssd"}}}' > c.yaml
# OR generate + edit:
kubectl run cache --image=redis $do > c.yaml
# add under spec:
#   nodeSelector:
#     disk: ssd
kubectl apply -f c.yaml
```
</details>

### 2. Taint a node, schedule a tolerating pod

> Taint `node-1` so only "database" workloads land there. Then schedule a pod with that toleration.

<details><summary>Solution</summary>

```bash
kubectl taint nodes node-1 workload=db:NoSchedule
```

Pod manifest:
```yaml
apiVersion: v1
kind: Pod
metadata: { name: db }
spec:
  tolerations:
  - key: workload
    operator: Equal
    value: db
    effect: NoSchedule
  containers:
  - { name: db, image: postgres:15 }
```
</details>

### 3. Anti-affinity for HA

> Deployment `web` (3 replicas) should run one-per-node.

<details><summary>Solution</summary>

```yaml
spec:
  replicas: 3
  template:
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels: { app: web }
            topologyKey: kubernetes.io/hostname
```

Verify: `kubectl get pods -o wide` — each on a different node. If you have only 2 nodes and replicas=3, one pod stays Pending. That's the constraint working as designed.
</details>

### 4. Topology spread across zones

> 6 replicas should be spread across 3 zones (`zone-a/b/c`), no more than skew of 1.

<details><summary>Solution</summary>

```yaml
spec:
  replicas: 6
  template:
    metadata:
      labels: { app: api }
    spec:
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels: { app: api }
      containers:
      - { name: api, image: my/api }
```
</details>

### 5. Drain blocked by daemonset

> `kubectl drain node-2` errors: "DaemonSet-managed Pods: kube-proxy-xyz".

<details><summary>Solution</summary>

```bash
kubectl drain node-2 --ignore-daemonsets --delete-emptydir-data
```

DaemonSet pods can't be evicted (controller would just recreate them); `--ignore-daemonsets` lets the drain proceed.
</details>

### 6. Pod Pending — why?

> Pod `analytics` is `Pending`. Find the reason.

<details><summary>Solution</summary>

```bash
kubectl describe pod analytics
# Look at Events at the bottom:
#   "0/3 nodes are available: 3 Insufficient cpu"      → resources
#   "0/3 nodes are available: 3 node(s) had untolerated taint" → taint
#   "0/3 nodes are available: 3 node(s) didn't match node selector" → nodeSelector
```

Fix accordingly: scale cluster, reduce requests, add toleration, fix label, etc.
</details>

---

## Common pitfalls

| Pitfall | Outcome |
|---|---|
| No `resources.requests` set | BestEffort QoS; pod evicted first under pressure |
| CPU limit set too low | Throttling, latency spikes (CPU is compressible) |
| Memory limit set too low | **OOMKilled** (memory is not compressible) |
| Heavy `podAffinity` rules | Slow scheduling at scale |
| Forgot toleration for control-plane | Pod won't land there (often intentional) |
| `topologyKey` references nonexistent label | All nodes are the "same" domain; constraint no-ops |
| Drained but didn't uncordon | Node permanently unschedulable; pods pile up elsewhere |

---

## Doc bookmarks

- https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/
- https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/
- https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/
- https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/
- https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/

---

## Speed drill

```bash
# Label / taint / cordon / drain combo
kubectl label node n2 disk=ssd
kubectl taint nodes n1 special=true:NoSchedule
kubectl taint nodes n1 special=true:NoSchedule-      # remove
kubectl cordon n1
kubectl drain n1 --ignore-daemonsets --delete-emptydir-data
kubectl uncordon n1

# Why pending?
kubectl describe pod <p> | tail -20
```
