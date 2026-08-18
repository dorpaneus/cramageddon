# Self-Healing Applications: Probes & Restart Policies

> **Objective (CNCF):** Implement and configure self-healing applications using probes, restart policies, and PodDisruptionBudgets.
> **Domain:** Workloads & Scheduling (15%) — **Exam frequency:** ⭐⭐⭐

---

## Why this matters

Kubernetes self-heals at multiple layers: container restarts (kubelet), pod rescheduling (controllers), traffic gating (probes). Expect tasks like *"Add a readiness probe to deployment X"* or *"This pod is in CrashLoopBackOff — fix it."*

---

## The three probe types

| Probe | What it does | Failure action |
|---|---|---|
| **livenessProbe** | "Is the container alive?" | kubelet **kills** the container; restart policy decides what's next |
| **readinessProbe** | "Is the container ready to serve traffic?" | Pod IP removed from **Service Endpoints** (no traffic routed) |
| **startupProbe** | "Has the slow-starting app finished booting?" | Disables liveness/readiness until it succeeds; then they take over |

**Critical mental model:**
- A failing liveness probe **kills**.
- A failing readiness probe **isolates** from Service traffic.
- A failing startup probe **gives slow apps time** without false-positive liveness kills.

---

## Probe handler types

Every probe has one of three handlers:

```yaml
httpGet:
  path: /healthz
  port: 8080
  httpHeaders:
  - name: X-Custom
    value: value
---
tcpSocket:
  port: 5432
---
exec:
  command: ["cat", "/tmp/ready"]
---
grpc:                       # K8s 1.24+
  port: 9000
  service: liveness
```

---

## Probe timing knobs (memorize defaults)

```yaml
livenessProbe:
  httpGet: { path: /healthz, port: 8080 }
  initialDelaySeconds: 0    # wait before first check
  periodSeconds: 10         # how often
  timeoutSeconds: 1         # per-probe timeout
  successThreshold: 1       # consecutive successes to mark healthy
  failureThreshold: 3       # consecutive failures to mark unhealthy
```

Defaults are usually fine. **Tune `initialDelaySeconds`** for slow apps — or better, use a startupProbe.

---

## Complete pod with all three probes

```yaml
apiVersion: v1
kind: Pod
metadata: { name: app }
spec:
  containers:
  - name: app
    image: my/app:1.0
    ports: [{ containerPort: 8080 }]
    startupProbe:
      httpGet: { path: /healthz, port: 8080 }
      failureThreshold: 30      # 30 * 10s = 5 minute startup budget
      periodSeconds: 10
    livenessProbe:
      httpGet: { path: /healthz, port: 8080 }
      periodSeconds: 10
      failureThreshold: 3
    readinessProbe:
      httpGet: { path: /ready, port: 8080 }
      periodSeconds: 5
      failureThreshold: 2
```

While startupProbe runs, liveness and readiness are **disabled**. After startup succeeds, they take over.

---

## Restart policies

Set at pod level: `spec.restartPolicy`.

| Value | Behavior | Used in |
|---|---|---|
| `Always` | Restart container on any exit (success or failure) | **Default for Deployments, ReplicaSets, DaemonSets, StatefulSets** |
| `OnFailure` | Restart only on non-zero exit | Jobs (commonly) |
| `Never` | Don't restart; pod goes to Succeeded/Failed | Jobs (occasionally), debugging |

Restart policy controls **container** restarts inside a pod. Pod-level rescheduling (e.g., evicted node) is handled by the **controller** (Deployment recreates).

---

## CrashLoopBackOff — what it really is

The container exited repeatedly. Kubelet applies **exponential backoff**: 10s, 20s, 40s, 80s, ..., capped at 5 min.

**Debug recipe:**

```bash
kubectl describe pod <name>            # State, Last State, Reason, Exit Code
kubectl logs <name>                    # Current attempt
kubectl logs <name> --previous         # ⭐ Previous (crashed) container — the real evidence
kubectl logs <name> -c <container>     # If multi-container
```

Common causes:
- **Exit code 0** + restart `Always` → app finished cleanly; should be a Job, not a Deployment.
- **Exit code 137** → OOMKilled. Bump memory limit.
- **Exit code 1/2** → app crashed; logs will tell you why.
- **Bad command** → `kubectl describe` shows `RunContainerError` or `CreateContainerConfigError`.

---

## Liveness probe — the dangerous one

A misconfigured liveness probe **causes** outages: it kills healthy pods that just answer slowly.

**Anti-pattern:** Liveness probe hits `/login` which queries the database.
- DB slow → login slow → probe fails → pod killed → pod restarts → DB still slow → loop.
- Now you've turned a degradation into a full outage.

**Rules of thumb:**
- Liveness: hits a **trivial in-process** endpoint (`/healthz` that returns 200 unconditionally if the process is running).
- Readiness: hits the realistic endpoint that includes downstream checks. Failing readiness just removes from Service, doesn't kill.
- When in doubt, **omit liveness**. Readiness is usually enough.

---

## PodDisruptionBudget (PDB)

Limits voluntary disruptions (node drain, eviction) — **not** node failures (those are involuntary).

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: { name: web-pdb }
spec:
  minAvailable: 2           # OR: maxUnavailable: 1
  selector:
    matchLabels: { app: web }
```

When you `kubectl drain` a node, the eviction API respects PDBs:
```
error: cannot evict pod as it would violate the pod's disruption budget
```

This is why drains hang during exams — check PDBs.

---

## Exercises

### 1. Add a readiness probe

> Deployment `web` runs nginx on port 80. Add a readiness probe that hits `/` every 5s and gives up after 3 failures.

<details><summary>Solution</summary>

```bash
kubectl edit deploy web
```
Add under the container:
```yaml
readinessProbe:
  httpGet: { path: /, port: 80 }
  periodSeconds: 5
  failureThreshold: 3
```

Or in one shot:
```bash
kubectl patch deploy web --type=json -p='[{"op":"add","path":"/spec/template/spec/containers/0/readinessProbe","value":{"httpGet":{"path":"/","port":80},"periodSeconds":5,"failureThreshold":3}}]'
```
</details>

### 2. Slow-starting Java app

> Pod runs a Java app that needs ~3 minutes to warm up. Liveness probe kills it before it's ready. Fix it.

<details><summary>Solution</summary>

Add a **startupProbe** that allows up to ~5 minutes before liveness kicks in:

```yaml
startupProbe:
  httpGet: { path: /healthz, port: 8080 }
  failureThreshold: 30        # 30 * 10s = 5 min
  periodSeconds: 10
livenessProbe:
  httpGet: { path: /healthz, port: 8080 }
  periodSeconds: 10
```

(Old approach: bumping `initialDelaySeconds: 180` on liveness. Works, but startupProbe is cleaner because once the app is up, you get fast liveness checks.)
</details>

### 3. CrashLoopBackOff investigation

> Pod `web` is `CrashLoopBackOff`. Find the cause.

<details><summary>Solution</summary>

```bash
kubectl describe pod web
# Look for:
#   Last State: Terminated, Reason: ___, Exit Code: ___
#   Events at bottom

kubectl logs web --previous
# Logs from the crashed container — usually the smoking gun

kubectl get pod web -o jsonpath='{.status.containerStatuses[0].lastState}'
```

Then fix according to the exit code / log message.
</details>

### 4. PDB for a HA web app

> Deployment `web` has 5 replicas. Create a PDB so at least 4 are always available during drains.

<details><summary>Solution</summary>

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: { name: web-pdb }
spec:
  minAvailable: 4
  selector:
    matchLabels: { app: web }
```

```bash
kubectl apply -f web-pdb.yaml
kubectl get pdb
# NAME      MIN AVAILABLE   ALLOWED DISRUPTIONS
# web-pdb   4               1
```
</details>

### 5. Drain blocked by PDB

> `kubectl drain node-1` hangs with "cannot evict pod ... violate disruption budget". You need to drain. What's safe?

<details><summary>Solution</summary>

Options, in order of preference:
1. **Wait** — replicas may scale up on other nodes first.
2. **Scale up** the Deployment temporarily so the PDB allows eviction:
   ```bash
   kubectl scale deploy web --replicas=6
   ```
3. **Loosen the PDB** temporarily (`minAvailable: 3`), drain, restore.
4. Only in emergencies: `kubectl drain node-1 --disable-eviction --force` (skips the eviction API — **never** without an explicit reason; it's a foot-gun).
</details>

---

## Common pitfalls

| Pitfall | Why it hurts |
|---|---|
| Liveness probe queries the database | One slow dependency → cascading restart storm |
| `initialDelaySeconds` too short for slow apps | App killed mid-startup, restart loop |
| No `readinessProbe` on apps that warm caches | Service sends traffic to a not-ready pod → 5xx |
| `successThreshold: 5` on a liveness probe | **Invalid** — successThreshold must be 1 for liveness/startup |
| PDB with `minAvailable: 100%` | Node drains permanently blocked |
| Confusing pod `restartPolicy` with controller behavior | Controller recreates pods; restartPolicy is for containers inside a pod |

---

## Doc bookmarks

- https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/
- https://kubernetes.io/docs/concepts/workloads/pods/disruptions/
- https://kubernetes.io/docs/tasks/run-application/configure-pdb/

---

## Speed drill

```bash
# Add a probe imperatively-ish: edit + paste
kubectl get deploy web -o yaml > w.yaml
# add probe block
kubectl apply -f w.yaml

# Or patch
kubectl patch deploy web --type=json -p='[{"op":"add","path":"/spec/template/spec/containers/0/livenessProbe","value":{"httpGet":{"path":"/healthz","port":8080},"periodSeconds":10}}]'
```
