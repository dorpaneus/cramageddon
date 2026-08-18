# Autoscaling: HPA (and a Note on VPA)

> **Objective (CNCF):** Implement and configure self-healing applications including autoscaling (HPA, VPA awareness).
> **Domain:** Workloads & Scheduling (15%) — **Exam frequency:** ⭐⭐⭐ (NEW emphasis in 2025 refresh)

---

## Why this matters

The CKA 2025 refresh added autoscaling explicitly. HPA is the workhorse: it scales Deployments/StatefulSets/ReplicaSets horizontally based on metrics. Expect a task like *"Create an HPA for deployment X with min 2, max 10, CPU target 60%."*

---

## Core concepts

```
                    ┌────────────────────┐
                    │  metrics-server    │  (cluster add-on, must be running)
                    └─────────┬──────────┘
                              │ provides pod CPU/mem
                              ▼
   ┌──────────────┐   reads   ┌──────────────────────┐  scales   ┌──────────────┐
   │     HPA      │──────────▶│  metrics.k8s.io API  │──────────▶│  Deployment  │
   │  (controller)│           └──────────────────────┘           │  replicas    │
   └──────────────┘                                              └──────────────┘
```

- **HPA** = HorizontalPodAutoscaler — adjusts `spec.replicas` based on observed metrics.
- **VPA** = VerticalPodAutoscaler — adjusts CPU/memory **requests** (not a built-in resource; add-on). **Awareness only** for the exam.
- **metrics-server** must be installed. Without it, HPA reports `<unknown>` and never scales.

### Algorithm (simplified)

```
desiredReplicas = ceil(currentReplicas * (currentMetric / targetMetric))
```

If target CPU is 50% and current is 80% across 4 pods → `ceil(4 * 80/50) = 7`.

HPA refuses to flap: there is a **stabilization window** (default 5 min on scale-down, 0 on scale-up).

---

## Prerequisites

The Deployment **must** declare `resources.requests.cpu` (and memory if you target memory). HPA computes utilization as `usage / request`. Without a request, utilization is undefined.

```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
```

---

## Install metrics-server (lab)

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# In a kind/dev cluster (self-signed kubelet certs), patch to allow insecure TLS:
kubectl -n kube-system patch deploy metrics-server --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

# Verify
kubectl top nodes
kubectl top pods -A
```

If `kubectl top` returns "Metrics API not available," metrics-server isn't running or hasn't aggregated yet (wait ~30s).

---

## Create an HPA — imperative (fastest in exam)

```bash
kubectl autoscale deployment web --min=2 --max=10 --cpu-percent=60
# kubectl get hpa
# NAME   REFERENCE        TARGETS         MINPODS   MAXPODS   REPLICAS
# web    Deployment/web   <unknown>/60%   2         10        2
```

Wait ~30s for metrics to populate. `<unknown>` becomes a real number.

---

## Declarative HPA (autoscaling/v2 — the modern API)

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: web
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: web
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 60
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 75
  behavior:                              # OPTIONAL — controls scale speed
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
      - type: Percent
        value: 100
        periodSeconds: 30
      - type: Pods
        value: 4
        periodSeconds: 30
      selectPolicy: Max
```

When multiple metrics are listed, HPA computes a replica count for each and picks the **highest**.

---

## Inspect / debug

```bash
kubectl get hpa
kubectl describe hpa web                 # Events show scaling decisions

# Force load to trigger scale-up
kubectl run load --image=busybox --restart=Never -- \
  /bin/sh -c "while true; do wget -q -O- http://web.default.svc; done"

kubectl top pods                         # Watch CPU climb
kubectl get hpa -w                       # Watch replicas grow
```

---

## Common targets and their YAML

**CPU utilization (most common):**
```yaml
- type: Resource
  resource: { name: cpu, target: { type: Utilization, averageUtilization: 70 } }
```

**Absolute value (rare):**
```yaml
- type: Resource
  resource: { name: cpu, target: { type: AverageValue, averageValue: 200m } }
```

**Pod-level custom metric (queue depth, etc.):**
```yaml
- type: Pods
  pods:
    metric: { name: queue_messages_ready }
    target: { type: AverageValue, averageValue: "30" }
```
(Custom metrics need a custom-metrics adapter — out of scope for CKA, but recognize the shape.)

---

## VPA — what to know (awareness only)

- Adjusts pod **resource requests** vertically (more CPU, more RAM) instead of adding replicas.
- Not built into Kubernetes; installed as `kubernetes-sigs/vertical-pod-autoscaler`.
- Modes: `Off` (recommendations only), `Initial` (set on creation), `Auto` (evicts pods to apply new requests).
- **Don't combine VPA and HPA on the same resource metric** — they fight.

Exam won't ask you to configure VPA. Be able to say one sentence about it.

---

## Exercises

### 1. Quick HPA

> Deployment `nginx` exists in `default`. Create an HPA: min 1, max 5, CPU target 80%.

<details><summary>Solution</summary>

```bash
kubectl autoscale deployment nginx --min=1 --max=5 --cpu-percent=80
kubectl get hpa nginx
```
</details>

### 2. HPA with declarative manifest

> Create an HPA `api-hpa` for Deployment `api` that scales between 3 and 20 pods, targeting **70% CPU** and **80% memory**.

<details><summary>Solution</summary>

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: { name: api-hpa }
spec:
  scaleTargetRef: { apiVersion: apps/v1, kind: Deployment, name: api }
  minReplicas: 3
  maxReplicas: 20
  metrics:
  - type: Resource
    resource: { name: cpu, target: { type: Utilization, averageUtilization: 70 } }
  - type: Resource
    resource: { name: memory, target: { type: Utilization, averageUtilization: 80 } }
```

```bash
kubectl apply -f api-hpa.yaml
kubectl describe hpa api-hpa
```
</details>

### 3. HPA shows `<unknown>` — diagnose

> `kubectl get hpa` shows `TARGETS: <unknown>/60%` for 5 minutes. What do you check?

<details><summary>Solution</summary>

1. **metrics-server running?**
   ```bash
   kubectl -n kube-system get deploy metrics-server
   kubectl top pods                        # Must return data
   ```
2. **Pod requests set?** Check the Deployment:
   ```bash
   kubectl get deploy web -o yaml | grep -A3 resources
   ```
   If `requests.cpu` is missing, HPA cannot compute utilization. Add it.
3. **Recent rollout?** Wait 30s for metrics to populate after pod start.
</details>

### 4. Slow down scale-down

> An HPA scales pods down aggressively, causing thrashing. Make it wait 10 minutes before reducing replicas.

<details><summary>Solution</summary>

Edit the HPA and add a `behavior` block:

```yaml
spec:
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 600
```

```bash
kubectl edit hpa <name>
```
</details>

---

## Common pitfalls

| Symptom | Cause |
|---|---|
| `TARGETS: <unknown>/...` | metrics-server missing **or** no resource requests on pods |
| HPA never scales above minReplicas under load | Target % too high, or wrong metric, or insufficient load duration |
| Replicas oscillate | Scale-down stabilization too short; raise `stabilizationWindowSeconds` |
| HPA conflicts with manual `kubectl scale` | HPA owns replicas — manual scale is overridden |
| `autoscaling/v1` vs `v2` | v1 supports CPU only. **Always use `autoscaling/v2`** for the exam. |

---

## Doc bookmarks

- https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/
- https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/
- https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.34/#horizontalpodautoscaler-v2-autoscaling

---

## Speed drill

Goal: HPA from scratch in **≤ 60 seconds**.

```bash
kubectl create deploy web --image=nginx --replicas=2
kubectl set resources deploy web --requests=cpu=100m,memory=128Mi
kubectl autoscale deploy web --min=2 --max=10 --cpu-percent=70
kubectl get hpa
```
