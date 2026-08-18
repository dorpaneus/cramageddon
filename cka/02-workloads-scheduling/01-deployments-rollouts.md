# 2.1 — Deployments, Rolling Updates, and Rollbacks

> **Objective:** Understand deployments and how to perform rolling update and rollbacks.
> **Exam frequency:** Very high — at least one Deployment task.

## 🎯 Why this matters

`Deployment` is the workhorse. You will absolutely create, scale, update, and roll back one in the exam.

## 🧠 Core hierarchy

```
Deployment   (manages multiple ReplicaSets — for rollouts)
   ↓
ReplicaSet   (manages N identical Pods)
   ↓
Pod          (one or more containers, sharing network + storage)
```

When you `kubectl apply` a Deployment update:
1. Deployment creates a **new ReplicaSet** with the new spec
2. New RS scales up gradually; old RS scales down
3. `maxSurge` and `maxUnavailable` control the pace
4. Old RS is kept (default: last 10) — that's what `rollback` uses

## 🛠️ Imperative quick wins

```bash
# Create a Deployment
k create deployment web --image=nginx:1.25 --replicas=3

# Generate YAML, don't create (THE most useful pattern)
k create deployment web --image=nginx:1.25 --replicas=3 $do > web.yaml
# remember: export do='--dry-run=client -o yaml'

# Edit + apply
vi web.yaml
k apply -f web.yaml

# Scale
k scale deployment web --replicas=5

# Update image (the classic rolling update)
k set image deployment/web nginx=nginx:1.26

# Watch the rollout
k rollout status deployment/web

# History
k rollout history deployment/web
k rollout history deployment/web --revision=2

# Rollback to previous
k rollout undo deployment/web

# Rollback to specific revision
k rollout undo deployment/web --to-revision=2

# Pause / resume (useful when applying multiple changes atomically)
k rollout pause deployment/web
k set image deployment/web nginx=nginx:1.27
k set resources deployment/web -c=nginx --limits=cpu=200m,memory=512Mi
k rollout resume deployment/web

# Restart all pods (no spec change — useful after secret/configmap update)
k rollout restart deployment/web
```

## 📄 Anatomy of a Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: default
  labels:
    app: web
spec:
  replicas: 3
  revisionHistoryLimit: 10                # how many old RSs to keep
  strategy:
    type: RollingUpdate                   # or Recreate
    rollingUpdate:
      maxSurge: 25%                       # extra pods above replicas during update
      maxUnavailable: 25%                 # how many can be down at once
  selector:
    matchLabels:
      app: web                            # MUST match template.metadata.labels
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: nginx
        image: nginx:1.25
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 10
```

### `strategy.type`

| Type | Behavior |
| --- | --- |
| `RollingUpdate` (default) | Gradual replacement, zero-downtime |
| `Recreate` | Kill all old → start all new. Brief downtime. Useful for non-HA stateful apps. |

### `maxSurge` and `maxUnavailable`

Can be absolute (`maxSurge: 2`) or percentage (`maxSurge: 25%`). With `replicas: 4`:
- `maxSurge: 1` → at most 5 pods during update
- `maxUnavailable: 1` → at most 1 unavailable, so 3 always ready

## 🔁 Other workload kinds (be aware)

| Kind | When to use |
| --- | --- |
| `ReplicaSet` | Rarely directly — Deployment wraps it |
| `DaemonSet` | One pod per node (logging, monitoring agents) |
| `StatefulSet` | Stable pod identity, ordered scaling, per-pod PVC |
| `Job` | Run-to-completion task |
| `CronJob` | Schedule a Job on a cron expression |

### DaemonSet example

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: log-agent
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: log-agent
  template:
    metadata:
      labels:
        app: log-agent
    spec:
      tolerations:                                # to also schedule on control plane
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      containers:
      - name: agent
        image: fluentd:v1.17
        volumeMounts:
        - name: varlog
          mountPath: /var/log
      volumes:
      - name: varlog
        hostPath:
          path: /var/log
```

### StatefulSet essentials

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: db
spec:
  serviceName: db                                 # must reference a headless Service
  replicas: 3
  selector:
    matchLabels:
      app: db
  template:
    metadata:
      labels:
        app: db
    spec:
      containers:
      - name: postgres
        image: postgres:16
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
```

Pods get stable names: `db-0`, `db-1`, `db-2`. Each gets its own PVC: `data-db-0`, `data-db-1`, `data-db-2`.

### Job and CronJob

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: pi
spec:
  completions: 5            # run 5 times
  parallelism: 2            # 2 at a time
  backoffLimit: 4           # retry up to 4 times on failure
  template:
    spec:
      restartPolicy: Never  # MUST be Never or OnFailure for Jobs
      containers:
      - name: pi
        image: perl
        command: ["perl", "-Mbignum=bpi", "-wle", "print bpi(2000)"]
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: nightly-backup
spec:
  schedule: "0 2 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: backup
            image: backup-tool:1.0
            command: ["/bin/sh","-c","echo backup"]
```

## 🏋️ Exam-style exercises

### Exercise 1
Create a Deployment named `web` with image `nginx:1.25`, 4 replicas, in namespace `frontend`. Then update to `nginx:1.26` and watch the rollout. Then roll back.

<details><summary>Solution</summary>

```bash
k create namespace frontend
k create deployment web --image=nginx:1.25 --replicas=4 -n frontend
k set image deployment/web nginx=nginx:1.26 -n frontend
k rollout status deployment/web -n frontend
k rollout history deployment/web -n frontend
k rollout undo deployment/web -n frontend
k rollout status deployment/web -n frontend
```
</details>

### Exercise 2
Create a Deployment from YAML named `api` with 3 replicas of `httpd:2.4`. The rolling update strategy must allow only 1 pod down at a time and at most 1 extra pod during update.

<details><summary>Solution</summary>

```bash
k create deployment api --image=httpd:2.4 --replicas=3 $do > api.yaml
```

Edit:
```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1
```

```bash
k apply -f api.yaml
```
</details>

### Exercise 3
A Deployment `web` has a buggy image `nginx:bad`. The previous revision was `nginx:1.25`. Roll it back without specifying the image — just use rollout commands.

<details><summary>Solution</summary>

```bash
k rollout history deployment/web
# pick the revision that has nginx:1.25
k rollout undo deployment/web --to-revision=<N>
k rollout status deployment/web
```
</details>

### Exercise 4
A DaemonSet `monitor` runs on every worker node but doesn't run on the control plane. Add a toleration so it also runs there.

<details><summary>Solution</summary>

```bash
k edit ds monitor
```
Add under `spec.template.spec`:
```yaml
tolerations:
- key: node-role.kubernetes.io/control-plane
  operator: Exists
  effect: NoSchedule
```
</details>

### Exercise 5
Create a CronJob `cleanup` that runs every 5 minutes, running `busybox` with command `echo cleanup`. Keep only 3 successful job history records.

<details><summary>Solution</summary>

```bash
k create cronjob cleanup --image=busybox --schedule="*/5 * * * *" -- /bin/sh -c "echo cleanup" $do > cj.yaml
```
Edit:
```yaml
spec:
  schedule: "*/5 * * * *"
  successfulJobsHistoryLimit: 3
  jobTemplate:
    ...
```
```bash
k apply -f cj.yaml
```
</details>

## ⚠️ Common pitfalls

- **`spec.selector.matchLabels` must match `spec.template.metadata.labels`.** Mismatch = `selector does not match template labels` error.
- **Forgetting `restartPolicy: Never` or `OnFailure` for Jobs.** Default `Always` fails.
- **Updating a Deployment's selector** — **forbidden** after creation. Delete and recreate.
- **`kubectl edit` saved badly** — kubectl writes to `/tmp/`. If you exit with `:q!` it discards but if you save with errors the apply step fails.
- **Forgetting `--namespace`** — most exam tasks specify one.

## 📚 Doc bookmarks

- [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
- [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/)
- [Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/)
- [CronJob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/)

## 🔁 Speed drills

| Drill | Target |
| --- | --- |
| Create Deployment from YAML, 3 replicas, nginx | < 90 s |
| Rolling update + rollback | < 60 s |
| Create CronJob every minute | < 60 s |
