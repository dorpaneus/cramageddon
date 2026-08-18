# Objective 9 — Configure Application Security

> **Exam study points:**
> - Configure and manage service accounts
> - Run privileged applications
> - Manage and apply permissions using security context constraints
> - Create and apply secrets to manage sensitive information
> - Configure application access to Kubernetes APIs
> - Deploy jobs to perform one-time tasks
> - Configure Kubernetes cron jobs

This objective combines OpenShift's flagship security primitive (SCC) with batch workloads (Jobs / CronJobs). Common exam scenario: a stock image refuses to run because of SCC; you bind a Service Account to an appropriate SCC and the pod recovers.

---

## §1 — ServiceAccounts (SA)

Every pod runs **as some SA**. If you don't specify one, it's `default` in that namespace.

```bash
# Create
oc create sa mysa

# List
oc get sa -n myapp

# Tell a Deployment to use it
oc set serviceaccount deployment/hello mysa
# OR in YAML:
spec:
  template:
    spec:
      serviceAccountName: mysa
```

SAs have:

- **Tokens** auto-mounted at `/var/run/secrets/kubernetes.io/serviceaccount/token` (used to call the Kubernetes API)
- **Image pull secrets** (linked via `oc secrets link <sa> <secret> --for=pull`)
- **RBAC bindings** (you can `oc adm policy add-role-to-user view -z mysa` — the `-z` flag means "service account")

### Granting an SA permissions on the Kubernetes API

```bash
# Inside its own namespace
oc adm policy add-role-to-user edit -z mysa -n myapp

# Cluster-wide
oc adm policy add-cluster-role-to-user view -z mysa -n myapp

# Use the SA token from within a pod
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
curl -k -H "Authorization: Bearer $TOKEN" \
  https://kubernetes.default.svc/api/v1/namespaces/myapp/pods
```

## §2 — Security Context Constraints (SCC)

SCC is OpenShift's mechanism to control **what a pod is allowed to do at the host level**: run as root? Use host network? Mount host paths? It's enforced by an admission controller.

### The built-in SCCs (most → least permissive)

| SCC | Allows | Typical use |
|-----|--------|-------------|
| `privileged` | Everything — root, host network, host paths, all caps | Cluster-level workloads only |
| `anyuid` | Any UID (including 0); drops most caps | Stock community images that hardcode UID 0 |
| `hostmount-anyuid` | anyuid + host-path mounts | NFS provisioners, etc. |
| `hostnetwork` | Host network/PID/IPC | Ingress/router-like pods |
| `hostaccess` | All of the above except privileged | Hyper-converged storage |
| `nonroot-v2` | Any non-root UID | Modern non-root containers (default in 4.18) |
| `nonroot` | Like nonroot-v2 but older API | Legacy |
| `restricted-v2` (default) | Random UID, no caps, no root | All standard workloads (default for `system:authenticated`) |
| `restricted` | Older variant of restricted-v2 | Legacy compatibility |

### List and inspect

```bash
oc get scc
oc describe scc restricted-v2

# Which SCC was a pod admitted under?
oc get pod mypod -o yaml | grep openshift.io/scc
```

### Binding an SCC to an SA (the canonical task)

Wrong way: editing the SCC's `users:` list (works but doesn't scale).
**Right way:** bind via RBAC.

```bash
# Grant "use" permission on a single SCC to a Service Account
oc adm policy add-scc-to-user anyuid -z mysa -n myapp

# Same thing via a Role you can audit
# (oc adm policy actually creates a Role/RB for you under the hood in 4.18)

# Remove
oc adm policy remove-scc-from-user anyuid -z mysa -n myapp
```

### Common SCC scenario: an image expects root

```bash
oc new-project sccdemo

# This image runs as root (UID 0). On restricted-v2 it gets killed.
oc new-app --name=mongo --image=docker.io/bitnami/mongodb:6.0

oc get pods                  # CrashLoopBackOff
oc logs <pod>                # "could not chmod ... permission denied"

# Fix: dedicated SA + anyuid SCC
oc create sa mongo-sa
oc adm policy add-scc-to-user anyuid -z mongo-sa
oc set serviceaccount deployment/mongo mongo-sa
oc rollout status deploy/mongo
```

### Pod Security Admission (PSA) in 4.18

In OCP 4.18, the **PodSecurityAdmission** (Kubernetes-native) layer is enforced **alongside** SCCs. Each namespace carries labels:

```yaml
metadata:
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

If you give an SA the `anyuid` SCC but the namespace's PSA enforce label is `restricted`, the pod is **still rejected**. Two fixes:

```bash
# Option 1: relax the namespace
oc label ns sccdemo pod-security.kubernetes.io/enforce=privileged --overwrite
oc label ns sccdemo pod-security.kubernetes.io/warn=privileged --overwrite
oc label ns sccdemo pod-security.kubernetes.io/audit=privileged --overwrite

# Option 2: set a less restrictive global default via the Authentication operator (less common)
```

Always check both layers on exam: SCC + PSA.

## §3 — Privileged workloads

Sometimes you really do need a privileged pod (CSI drivers, node tools).

```yaml
apiVersion: v1
kind: Pod
metadata: { name: priv-pod }
spec:
  serviceAccountName: priv-sa
  containers:
    - name: c
      image: registry.access.redhat.com/ubi9/ubi
      command: ["sleep","3600"]
      securityContext:
        privileged: true
        runAsUser: 0
```

Then:

```bash
oc create sa priv-sa
oc adm policy add-scc-to-user privileged -z priv-sa
oc label ns <ns> pod-security.kubernetes.io/enforce=privileged --overwrite
oc apply -f priv-pod.yaml
```

> 🛑 **Never give `privileged` SCC to the `default` SA in a namespace** — that effectively makes every pod privileged. Always create a purpose-built SA.

## §4 — Secrets (security-flavored recap)

```bash
# Generic
oc create secret generic api-key --from-literal=key=abc123

# Mount as env var (one key)
spec.containers[].env:
- name: API_KEY
  valueFrom:
    secretKeyRef: { name: api-key, key: key }

# Mount as a file (entire secret)
spec.containers[].volumeMounts:
- { name: api-key-vol, mountPath: /etc/api, readOnly: true }
spec.volumes:
- name: api-key-vol
  secret: { secretName: api-key, defaultMode: 0400 }
```

### Pull secrets for private registries

```bash
oc create secret docker-registry myreg \
  --docker-server=quay.io --docker-username=u --docker-password=p
oc secrets link default myreg --for=pull            # for the default SA
oc secrets link builder myreg                        # also for builds
```

## §5 — Jobs: one-shot tasks

A `Job` runs N pods to completion. The pod can be retried on failure.

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migrate
spec:
  backoffLimit: 4                # retries on failure
  ttlSecondsAfterFinished: 600   # auto-delete 10 min after completion
  template:
    spec:
      restartPolicy: OnFailure
      containers:
        - name: migrate
          image: registry.redhat.io/rhel9/postgresql-15:latest
          command: ["psql", "-f", "/sql/migrate.sql", "$(DB_URL)"]
          env:
            - name: DB_URL
              valueFrom: { secretKeyRef: { name: dbcreds, key: url } }
          volumeMounts:
            - { name: sql, mountPath: /sql }
      volumes:
        - name: sql
          configMap: { name: migrations }
```

```bash
oc apply -f job.yaml
oc get jobs
oc get pods -l job-name=db-migrate
oc logs job/db-migrate
oc delete job db-migrate
```

### Parallel jobs

```yaml
spec:
  parallelism: 3        # how many pods run at once
  completions: 10       # how many must succeed
```

### Imperative

```bash
oc create job onetime --image=registry.access.redhat.com/ubi9/ubi -- /bin/sh -c "echo hello"
```

## §6 — CronJobs: scheduled tasks

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: nightly-backup
spec:
  schedule: "0 2 * * *"                      # 02:00 every day
  timeZone: "UTC"                            # k8s 1.27+ supports tz
  concurrencyPolicy: Forbid                  # Forbid / Allow / Replace
  startingDeadlineSeconds: 300
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: backup
              image: registry.access.redhat.com/ubi9/ubi
              command: ["/bin/sh","-c","echo backing up at $(date) && sleep 5"]
```

```bash
oc apply -f cronjob.yaml
oc get cronjob
oc get jobs --watch
oc logs job/nightly-backup-28543210
```

### Imperative

```bash
oc create cronjob ping --image=busybox --schedule="*/5 * * * *" -- ping -c 4 redhat.com
```

### Test a CronJob right now without waiting for the schedule

```bash
oc create job --from=cronjob/nightly-backup manual-run-1
```

---

## 🧪 Labs

### Lab 9.1 — SCC rescue (25 min)

The single most common security task on the exam: an app crashes because its container wants to run as a UID the default `restricted-v2` SCC forbids, and you have to grant it the least-permissive SCC (via a ServiceAccount) to make it run.

**Prerequisites:**
- Cluster-admin (needed to grant SCCs).
- Project: `oc new-project lab91`.

---

#### Step 1 — Deploy MongoDB and confirm it crashes

<details>
<summary>💡 Solution</summary>

```bash
oc project lab91
oc new-app --image=docker.io/bitnami/mongodb:6.0 --name=mongo
# --> Creating resources ...
#     deployment.apps "mongo" created
#     service "mongo" created

oc get pods -w
# NAME                     READY   STATUS             RESTARTS      AGE
# mongo-xxxxxxxxx-yyyyy    0/1     CrashLoopBackOff   3 (30s ago)   90s
```

`CrashLoopBackOff` — the container starts, fails immediately, and the kubelet keeps restarting it with exponential backoff.

**Why bitnami/mongodb specifically:** the bitnami image expects to run as a specific non-root UID and write to directories it owns. Under OpenShift's default `restricted-v2` SCC, the container is assigned a random high UID from the namespace's allocated range, which the image's files/dirs aren't owned by — so it can't write and dies.

</details>

---

#### Step 2 — Diagnose: logs show permission errors

<details>
<summary>💡 Solution</summary>

```bash
# Current container may be in backoff; use --previous to see the crashed instance's output
oc logs deploy/mongo
oc logs -p $(oc get pod -l deployment=mongo -o name | head -1)
```

Expect something like:

```
mkdir: cannot create directory '/bitnami/mongodb': Permission denied
...
chown: changing ownership of '/bitnami/mongodb': Operation not permitted
```

**Confirm it's an SCC/UID problem, not something else:**

```bash
# What SCC did the pod get admitted under?
oc get pod -l deployment=mongo \
  -o jsonpath='{.items[0].metadata.annotations.openshift\.io/scc}{"\n"}'
# restricted-v2

# What UID is the container forced to run as?
oc get pod -l deployment=mongo \
  -o jsonpath='{.items[0].spec.containers[0].securityContext}{"\n"}'
```

The `openshift.io/scc: restricted-v2` annotation plus permission-denied errors on file ownership is the classic signature of "this image needs a fixed UID / anyuid".

</details>

---

#### Step 3 — Create a ServiceAccount and bind the least-permissive SCC

<details>
<summary>💡 Solution</summary>

```bash
# 1. Create a dedicated ServiceAccount
oc create serviceaccount mongo-sa -n lab91

# 2. Grant it the anyuid SCC (lets the container run as the UID baked into the image)
oc adm policy add-scc-to-user anyuid -z mongo-sa -n lab91
# clusterrole.rbac.authorization.k8s.io/system:openshift:scc:anyuid added: "mongo-sa"
```

**The `-z` flag means "ServiceAccount"** (as opposed to a regular user). Always use `-z` when binding an SCC to a SA. Writing `add-scc-to-user anyuid mongo-sa` (without `-z`) would try to bind to a *user* named mongo-sa, which won't help the pod.

**Choosing the RIGHT SCC — least privilege matters on the exam:**

| SCC | Grants | Use when |
|-----|--------|----------|
| `restricted-v2` | Default. Random UID, no privileged, drops caps. | Well-behaved images |
| `nonroot-v2` | Any non-root UID the image requests (not random) | Image needs a *specific* non-root UID |
| `anyuid` | Any UID including a fixed one; still no host access | Image needs a fixed UID like 0-not-required but pinned (most "won't start" images) |
| `hostmount-anyuid` | anyuid + host path mounts | Backup/storage agents |
| `hostnetwork-v2` | Host networking + host ports | Ingress-like workloads |
| `privileged` | Everything. Root, host, all caps. | Last resort only |

For bitnami/mongodb, `anyuid` is correct. `privileged` would also work but is over-granting — the exam penalizes using a bigger hammer than needed.

**Verify what a SA is allowed:**

```bash
oc adm policy who-can use scc anyuid -n lab91
# or list SCCs a SA can use:
oc get rolebinding,clusterrolebinding -A -o wide 2>/dev/null | grep mongo-sa
```

</details>

---

#### Step 4 — Patch the Deployment to use the SA (and fix PSA labels if needed)

<details>
<summary>💡 Solution</summary>

```bash
# Point the Deployment's pod template at the new ServiceAccount
oc set serviceaccount deployment/mongo mongo-sa -n lab91
# deployment.apps/mongo serviceaccount updated

# (Equivalent patch form:)
# oc patch deployment mongo -n lab91 --type=merge \
#   -p '{"spec":{"template":{"spec":{"serviceAccountName":"mongo-sa"}}}}'
```

This triggers a new rollout. Watch:

```bash
oc rollout status deployment/mongo -n lab91
oc get pods -w
```

**PSA gotcha — SCC alone may not be enough in 4.18.** Pod Security Admission runs as a *separate* gate in front of SCC. If the namespace enforces `restricted` PSA, a pod requesting a fixed/root UID can be rejected at admission *before* the SCC ever mutates it. Symptoms: the Deployment shows a warning and pods never get created, with a message like:

```
Warning  FailedCreate  ...  Error creating: pods "mongo-..." is forbidden:
violates PodSecurity "restricted:v1.24": ...
```

If you hit that, relax the namespace's PSA enforce level:

```bash
# Check current PSA labels
oc get ns lab91 -o jsonpath='{.metadata.labels}{"\n"}' | tr ',' '\n' | grep pod-security

# Relax enforcement to privileged (baseline may suffice depending on the image)
oc label namespace lab91 \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/enforce-version=latest --overwrite
```

**Key mental model:** two independent gates, both must pass.

```
Pod admission → [ Pod Security Admission ] → [ SCC ] → Pod runs
                  (namespace labels)          (SA's granted SCC)
```

Granting `anyuid` via SCC fixes the SCC gate. Labeling the namespace fixes the PSA gate. A "won't start" image sometimes needs both.

</details>

---

#### Step 5 — Confirm the pod reaches `Ready 1/1`

<details>
<summary>💡 Solution</summary>

```bash
oc get pods -l deployment=mongo -n lab91
# NAME                     READY   STATUS    RESTARTS   AGE
# mongo-zzzzzzzzz-wwwww    1/1     Running   0          40s

# Confirm which SCC admitted it (should now be anyuid)
oc get pod -l deployment=mongo -n lab91 \
  -o jsonpath='{.items[0].metadata.annotations.openshift\.io/scc}{"\n"}'
# anyuid

# Confirm the pod is using the right ServiceAccount
oc get pod -l deployment=mongo -n lab91 \
  -o jsonpath='{.items[0].spec.serviceAccountName}{"\n"}'
# mongo-sa

# Logs should now show a healthy startup
oc logs deploy/mongo -n lab91 | tail
# ... "Waiting for connections" on port 27017
```

**Verification checklist for the rescue:**

```bash
oc get sa mongo-sa -n lab91                                                    # SA exists
oc get pod -l deployment=mongo -n lab91 -o jsonpath='{.items[0].metadata.annotations.openshift\.io/scc}'   # anyuid
oc get pod -l deployment=mongo -n lab91 -o jsonpath='{.items[0].status.phase}' # Running
```

**Cleanup:**

```bash
oc delete project lab91
```

</details>

---

### Lab 9.2 — SA + API access (20 min)

ServiceAccounts aren't just for SCCs — they're the identity a pod uses to talk to the Kubernetes API. This lab grants a SA read-only cluster access and proves it from inside a pod.

**Prerequisites:**
- Cluster-admin.
- Project: `oc new-project lab92`.

---

#### Step 1 — Create a ServiceAccount `viewer-sa`

<details>
<summary>💡 Solution</summary>

```bash
oc create serviceaccount viewer-sa -n lab92
# serviceaccount/viewer-sa created

oc get sa viewer-sa -n lab92
# NAME        SECRETS   AGE
# viewer-sa   0         5s        # (SECRETS shows 0 in 4.x — tokens are now projected, not static secrets)
```

**4.18 note on SA tokens:** Kubernetes 1.24+ (OCP 4.11+) stopped auto-creating a permanent Secret with a non-expiring token for each SA. Instead, pods get a short-lived, auto-rotated **projected** token mounted at `/var/run/secrets/kubernetes.io/serviceaccount/token`. That's why `SECRETS` reads 0. If you need a long-lived token for external use, you create it explicitly (shown in Step 4's notes).

</details>

---

#### Step 2 — Grant it the cluster role `view`

<details>
<summary>💡 Solution</summary>

```bash
# Cluster-wide view so the SA can read pods in OTHER namespaces (e.g. openshift-monitoring)
oc adm policy add-cluster-role-to-user view -z viewer-sa -n lab92
# clusterrole.rbac.authorization.k8s.io/view added: "system:serviceaccount:lab92:viewer-sa"
```

**The `-z viewer-sa -n lab92` shorthand** expands to the full SA username `system:serviceaccount:lab92:viewer-sa`. You could write it out longhand:

```bash
oc adm policy add-cluster-role-to-user view system:serviceaccount:lab92:viewer-sa
```

**cluster-role-to-user vs role-to-user:**

| Command | Scope |
|---------|-------|
| `add-cluster-role-to-user view -z sa` | View across ALL namespaces (ClusterRoleBinding) |
| `add-role-to-user view -z sa -n ns` | View only within namespace `ns` (RoleBinding) |

Since Step 4 reads pods in `openshift-monitoring`, we need the cluster-wide version here.

**Verify:**

```bash
oc auth can-i get pods -n openshift-monitoring \
  --as=system:serviceaccount:lab92:viewer-sa
# yes

oc auth can-i create deployments \
  --as=system:serviceaccount:lab92:viewer-sa -n lab92
# no
```

</details>

---

#### Step 3 — Deploy a pod that has CLI tools, running as `viewer-sa`

<details>
<summary>💡 Solution</summary>

```bash
cat <<'EOF' | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cli
  namespace: lab92
spec:
  replicas: 1
  selector:
    matchLabels: {app: cli}
  template:
    metadata:
      labels: {app: cli}
    spec:
      serviceAccountName: viewer-sa          # ← pod runs as this SA
      containers:
      - name: cli
        image: quay.io/openshift/origin-cli:latest
        command: ["sleep", "infinity"]
EOF

oc rollout status deployment/cli -n lab92
oc get pods -l app=cli -n lab92
# cli-xxxxx   1/1   Running
```

**Critical:** `serviceAccountName: viewer-sa` in the pod spec is what makes the pod use viewer-sa's token. Omit it and the pod uses the namespace's `default` SA (which has almost no permissions).

**If the origin-cli image won't start under restricted-v2** (it should, it's designed to), any UBI image with `oc`/`kubectl` works, or:

```bash
oc set image deployment/cli cli=registry.redhat.io/openshift4/ose-cli:latest -n lab92
```

</details>

---

#### Step 4 — From inside the pod, read pods in `openshift-monitoring` (should succeed)

<details>
<summary>💡 Solution</summary>

```bash
POD=$(oc get pod -l app=cli -n lab92 -o name | head -1)

# The pod's mounted token authenticates it automatically — oc/kubectl inside the
# pod default to the in-cluster config using the projected SA token.
oc exec -n lab92 $POD -- oc get pods -n openshift-monitoring
# NAME                  READY   STATUS    RESTARTS   AGE
# prometheus-k8s-0      6/6     Running   0          2d
# ... (succeeds because viewer-sa has cluster-wide view)
```

**How the in-pod auth works:** the kubelet mounts a projected token at `/var/run/secrets/kubernetes.io/serviceaccount/`. The `oc`/`kubectl` binaries auto-detect the in-cluster environment (`KUBERNETES_SERVICE_HOST` env var + that token path) and use it. No `oc login` needed inside the pod.

**Prove it with raw curl** (shows the mechanism explicitly):

```bash
oc exec -n lab92 $POD -- sh -c '
  TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
  CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
  curl -s --cacert $CACERT -H "Authorization: Bearer $TOKEN" \
    https://kubernetes.default.svc/api/v1/namespaces/openshift-monitoring/pods \
    | head -c 300
'
```

</details>

---

#### Step 5 — Try to create a Deployment (should be denied)

<details>
<summary>💡 Solution</summary>

```bash
oc exec -n lab92 $POD -- oc create deployment nope --image=bitnami/nginx:latest
# Error from server (Forbidden): deployments.apps is forbidden:
# User "system:serviceaccount:lab92:viewer-sa" cannot create resource "deployments"
# in API group "apps" in the namespace "lab92"
```

**Why it fails:** the `view` cluster role is read-only — it grants get/list/watch on most resources but no create/update/delete, and it explicitly excludes Secrets. This confirms least-privilege is working: the SA can observe the cluster but can't change anything.

**Contrast — grant edit and it would succeed:**

```bash
# (Don't run unless demonstrating) — this would let the pod create workloads:
# oc adm policy add-role-to-user edit -z viewer-sa -n lab92
# then the in-pod `oc create deployment` in lab92 would work.
```

**Bonus — create a long-lived token for external/CI use** (since 4.11+ doesn't auto-create one):

```bash
# Ephemeral token (default ~1h, bounded by cluster max):
oc create token viewer-sa -n lab92

# Longer duration:
oc create token viewer-sa -n lab92 --duration=24h

# Permanent token via explicit Secret (old-style, use sparingly):
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: viewer-sa-token
  namespace: lab92
  annotations:
    kubernetes.io/service-account.name: viewer-sa
type: kubernetes.io/service-account-token
EOF
oc get secret viewer-sa-token -n lab92 -o jsonpath='{.data.token}' | base64 -d
```

**Cleanup:**

```bash
oc delete project lab92
oc delete clusterrolebinding -l '' 2>/dev/null   # (the CRB from add-cluster-role-to-user is auto-named; find it if you want to purge)
oc get clusterrolebinding | grep viewer-sa       # then oc delete clusterrolebinding <name>
```

</details>

---

### Lab 9.3 — Job + Secret + ConfigMap (20 min)

Jobs run a task to completion (unlike Deployments, which run forever). This lab wires a Job to a ConfigMap (a file) and a Secret (env vars) — the common "run a DB migration" pattern.

**Prerequisites:**
- Project: `oc new-project lab93`.

---

#### Step 1 — Create a ConfigMap `migrations` with a fake `migrate.sql`

<details>
<summary>💡 Solution</summary>

```bash
# From a literal file
echo 'SELECT 1;' > migrate.sql
oc create configmap migrations --from-file=migrate.sql -n lab93

# (Alternative — inline literal)
# oc create configmap migrations --from-literal=migrate.sql='SELECT 1;' -n lab93

# Verify
oc get configmap migrations -n lab93 -o yaml
# data:
#   migrate.sql: |
#     SELECT 1;
```

**`--from-file` key naming:** `--from-file=migrate.sql` uses the filename as the key. To force a different key: `--from-file=script.sql=migrate.sql`. To load a whole directory: `--from-file=./sqldir/` (each file becomes a key).

</details>

---

#### Step 2 — Create a Secret `dbcreds` with a connection URL

<details>
<summary>💡 Solution</summary>

```bash
oc create secret generic dbcreds \
  --from-literal=url='postgres://user:pass@db:5432/app' \
  -n lab93

# Verify (value is base64-encoded at rest)
oc get secret dbcreds -n lab93 -o jsonpath='{.data.url}' | base64 -d; echo
# postgres://user:pass@db:5432/app
```

**Secret types recap:**

| Type | Create with | Use |
|------|-------------|-----|
| `generic` (Opaque) | `--from-literal` / `--from-file` | Arbitrary key/value |
| `docker-registry` | `oc create secret docker-registry` | Pull secrets |
| `tls` | `oc create secret tls --cert --key` | Route/ingress certs |

`generic` is what you want for a connection string.

</details>

---

#### Step 3 — Write a Job that consumes both (env from Secret, volume from ConfigMap)

<details>
<summary>💡 Solution</summary>

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migrate
  namespace: lab93
spec:
  backoffLimit: 4                    # retry up to 4 times on failure
  ttlSecondsAfterFinished: 300       # auto-delete the Job 5 min after it finishes
  template:
    spec:
      restartPolicy: Never           # Jobs use Never or OnFailure, never Always
      containers:
      - name: migrate
        image: registry.access.redhat.com/ubi9/ubi-minimal:latest
        command:
        - /bin/sh
        - -c
        - |
          echo "DB URL is: $DB_URL"
          echo "--- migrate.sql contents ---"
          cat /sql/migrate.sql
          echo "--- pretending to run migration ---"
          sleep 3
          echo "migration complete"
        env:
        - name: DB_URL
          valueFrom:
            secretKeyRef:
              name: dbcreds
              key: url
        volumeMounts:
        - name: sql
          mountPath: /sql
      volumes:
      - name: sql
        configMap:
          name: migrations
```

```bash
oc apply -f job.yaml
```

**The two wiring mechanisms shown:**

- **Secret → env var**: `env[].valueFrom.secretKeyRef` pulls one key into one environment variable. To pull *all* keys at once, use `envFrom: [{secretRef: {name: dbcreds}}]`.
- **ConfigMap → file**: mount the whole ConfigMap as a directory; each key becomes a file. Here `migrate.sql` appears at `/sql/migrate.sql`.

**Job-specific fields to know:**

| Field | Meaning |
|-------|---------|
| `restartPolicy` | Must be `Never` or `OnFailure` (not `Always`) |
| `backoffLimit` | Max retries before the Job is marked Failed (default 6) |
| `ttlSecondsAfterFinished` | Auto-cleanup delay after completion |
| `completions` | How many successful pods = done (default 1) |
| `parallelism` | How many pods run at once (default 1) |
| `activeDeadlineSeconds` | Hard wall-clock timeout for the whole Job |

</details>

---

#### Step 4 — Run, check logs, delete

<details>
<summary>💡 Solution</summary>

```bash
# Watch the Job complete
oc get job db-migrate -n lab93 -w
# NAME         COMPLETIONS   DURATION   AGE
# db-migrate   0/1           3s         3s
# db-migrate   1/1           6s         6s

# Read the pod's logs (the Job creates a pod named db-migrate-xxxxx)
oc logs job/db-migrate -n lab93
# DB URL is: postgres://user:pass@db:5432/app
# --- migrate.sql contents ---
# SELECT 1;
# --- pretending to run migration ---
# migration complete

# Inspect Job status
oc get job db-migrate -n lab93 -o jsonpath='{.status.succeeded}{"\n"}'
# 1

# Delete (or let ttlSecondsAfterFinished do it after 5 min)
oc delete job db-migrate -n lab93
```

**Gotcha — deleting a Job deletes its pods.** If you want to inspect a completed pod's logs, do it *before* deleting the Job (or before `ttlSecondsAfterFinished` fires). Once the Job is gone, so are its pods and their logs.

**Re-running a Job:** you can't just re-apply a completed Job with the same name — it's immutable once created. Delete it first, or use `oc create job db-migrate-2 --from=...`. This is different from Deployments.

**Cleanup:**

```bash
oc delete project lab93
```

</details>

---

### Lab 9.4 — CronJob with concurrency rules (20 min)

CronJobs create Jobs on a schedule. The exam-relevant nuance is `concurrencyPolicy` — what happens when a new run is due while the previous one is still going.

**Prerequisites:**
- Project: `oc new-project lab94`.

---

#### Step 1 — Create a CronJob that runs every minute and sleeps 90 s

The 90-second sleep with a 1-minute schedule guarantees overlap, so you can observe concurrency behavior.

<details>
<summary>💡 Solution</summary>

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: overlapper
  namespace: lab94
spec:
  schedule: "* * * * *"              # every minute
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: Never
          containers:
          - name: work
            image: registry.access.redhat.com/ubi9/ubi-minimal:latest
            command: ["/bin/sh","-c","echo start $(date +%T); sleep 90; echo done $(date +%T)"]
```

```bash
oc apply -f cronjob.yaml
oc get cronjob overlapper -n lab94
# NAME         SCHEDULE    SUSPEND   ACTIVE   LAST SCHEDULE   AGE
# overlapper   * * * * *   False     0        <none>          5s
```

**Cron schedule syntax (five fields):**

```
┌───────────── minute (0-59)
│ ┌─────────── hour (0-23)
│ │ ┌───────── day of month (1-31)
│ │ │ ┌─────── month (1-12)
│ │ │ │ ┌───── day of week (0-6, Sun=0)
│ │ │ │ │
* * * * *
```

Examples: `*/5 * * * *` = every 5 min; `0 2 * * *` = 2 AM daily; `0 0 * * 0` = midnight Sunday.

**Optional `timeZone` field (4.x):**

```yaml
spec:
  schedule: "0 9 * * *"
  timeZone: "America/New_York"       # otherwise schedule is interpreted in UTC
```

</details>

---

#### Step 2 — Set `concurrencyPolicy: Forbid` (one pod at a time)

<details>
<summary>💡 Solution</summary>

```bash
oc patch cronjob overlapper -n lab94 \
  --type=merge -p '{"spec":{"concurrencyPolicy":"Forbid"}}'
```

Or edit the YAML directly:

```yaml
spec:
  schedule: "* * * * *"
  concurrencyPolicy: Forbid
  jobTemplate:
    ...
```

**The three concurrency policies:**

| Policy | Behavior when a run is due but the previous is still running |
|--------|-------------------------------------------------------------|
| `Allow` (default) | Start the new run anyway — overlapping Jobs run in parallel |
| `Forbid` | Skip the new run; wait for the next tick after the current finishes |
| `Replace` | Kill the currently-running Job and start a fresh one |

With `Forbid` + a 90s task on a 60s schedule: the run at :00 takes until :90; the run scheduled at :01 is *skipped* (previous still active); the next run starts around :02 once the first completes.

</details>

---

#### Step 3 — Watch for 5 minutes; verify only one Job is `Active` at a time

<details>
<summary>💡 Solution</summary>

```bash
oc get jobs -n lab94 -w
# NAME                  COMPLETIONS   DURATION   AGE
# overlapper-28....     0/1           10s        10s     ← running
# (next-minute tick is SKIPPED because concurrencyPolicy=Forbid)
# overlapper-28....     1/1           92s        95s     ← first finished
# overlapper-28....     0/1           5s         5s      ← now the next one starts
```

**Watch the CronJob's ACTIVE count directly:**

```bash
watch -n5 'oc get cronjob overlapper -n lab94; echo; oc get jobs -n lab94'
# ACTIVE column stays at 1 (never 2) under Forbid
```

**Confirm skips in the events:**

```bash
oc describe cronjob overlapper -n lab94 | tail -15
# Events:
#   Type    Reason            Message
#   ----    ------            -------
#   Normal  JobAlreadyActive  Not starting job because prior execution is running and concurrencyPolicy is Forbid
```

That `JobAlreadyActive` event is the proof that Forbid is working.

</details>

---

#### Step 4 — Switch to `Replace` and observe pods replacing each other

<details>
<summary>💡 Solution</summary>

```bash
oc patch cronjob overlapper -n lab94 \
  --type=merge -p '{"spec":{"concurrencyPolicy":"Replace"}}'

oc get jobs -n lab94 -w
```

Now when the next minute ticks while a Job is still in its 90s sleep, OLM **deletes the running Job** (and its pod) and creates a new one:

```bash
oc describe cronjob overlapper -n lab94 | tail -15
# Events:
#   Normal  SawCompletedJob  ...
#   Normal  SuccessfulDelete  Deleted job overlapper-28....    ← the replace in action
#   Normal  SuccessfulCreate  Created job overlapper-28....
```

You'll see the ACTIVE Job's name change every minute, and the old pod terminate mid-sleep (it never reaches "done").

</details>

---

#### Step 5 — Trigger an ad-hoc run from the CronJob

Sometimes you need to run the job *now* without waiting for the schedule (e.g. to test it, or run an unplanned execution).

<details>
<summary>💡 Solution</summary>

```bash
oc create job manual-run --from=cronjob/overlapper -n lab94
# job.batch/manual-run created

oc get job manual-run -n lab94
oc logs job/manual-run -n lab94
# start 14:32:01
# ... (after 90s) ...
# done 14:33:31
```

`--from=cronjob/<name>` copies the CronJob's `jobTemplate` into a standalone Job that runs immediately and independently of the schedule and concurrency policy.

**Suspend the schedule** (stop future runs without deleting the CronJob):

```bash
oc patch cronjob overlapper -n lab94 --type=merge -p '{"spec":{"suspend":true}}'
# ACTIVE runs finish; no NEW runs are scheduled while suspend=true

# Resume:
oc patch cronjob overlapper -n lab94 --type=merge -p '{"spec":{"suspend":false}}'
```

**History limits** (how many finished Jobs to keep):

```yaml
spec:
  successfulJobsHistoryLimit: 3    # default 3
  failedJobsHistoryLimit: 1        # default 1
```

Lower these to avoid accumulating completed Jobs; the CronJob controller garbage-collects beyond the limit.

**Cleanup:**

```bash
oc delete project lab94
```

</details>

---

---

## ⚡ Drills (timed, no docs)

| Drill | Target time |
|-------|-------------|
| Create an SA and bind `anyuid` SCC to it | 30 s |
| Identify which SCC a pod was admitted under | 30 s |
| Bind `view` cluster role to an SA | 30 s |
| Write a Job YAML with backoffLimit + ttl | 90 s |
| Write a CronJob YAML running every weekday at 03:00 | 90 s |
| Trigger an immediate Job from an existing CronJob | 30 s |
| Make the `default` SA in a namespace able to pull from a private registry | 60 s |

---

## ❗ Common pitfalls

1. **Forgetting PSA**: SCC alone isn't enough on 4.18; check the namespace's `pod-security.kubernetes.io/enforce` label.
2. **Granting SCC to a user instead of an SA**: pods don't run as users — they run as SAs.
3. **`oc adm policy add-scc-to-user privileged -z default` is dangerous** — every pod in the namespace becomes privileged. Always use a dedicated SA.
4. **Job pods stick around** unless you set `ttlSecondsAfterFinished` — clutters the namespace.
5. **CronJob cron syntax is UTC by default**; use `spec.timeZone` if you need local time.
6. **`oc create job --from=cronjob/x` is the only way to "run now"** — there's no `oc trigger`.

## 🔗 Docs to bookmark

- ServiceAccounts: https://docs.openshift.com/container-platform/4.18/authentication_and_authorization/understanding-and-creating-service-accounts.html
- SCCs: https://docs.openshift.com/container-platform/4.18/authentication_and_authorization/managing-pod-security-policies.html
- Pod Security Admission: https://docs.openshift.com/container-platform/4.18/authentication_and_authorization/understanding-and-managing-pod-security-admission.html
- Jobs & CronJobs: https://docs.openshift.com/container-platform/4.18/nodes/jobs/nodes-nodes-jobs.html
