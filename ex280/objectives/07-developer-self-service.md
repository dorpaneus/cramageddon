# Objective 7 — Enable Developer Self-Service

> **Exam study points:**
> - Configure cluster resource quotas
> - Configure project quotas
> - Configure project resource requirements
> - Configure project limit ranges
> - Configure project templates

This objective is about giving developers safe boundaries: they can create things, but they can't blow up the cluster.

---

## §1 — ResourceQuota: total resources per project

A `ResourceQuota` caps the **sum** of certain resources in a single namespace.

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-quota
  namespace: team-alpha
spec:
  hard:
    # Compute
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "8"
    limits.memory: 16Gi
    # Counts
    pods: "20"
    services: "10"
    services.loadbalancers: "2"
    services.nodeports: "0"
    persistentvolumeclaims: "5"
    secrets: "30"
    configmaps: "30"
    # Storage
    requests.storage: 50Gi
```

```bash
oc apply -f quota.yaml
oc get resourcequota -n team-alpha
oc describe quota team-quota -n team-alpha
```

> 🔥 **Gotcha:** once a `ResourceQuota` covering `requests.cpu` or `requests.memory` exists, **every pod** in the namespace must declare requests/limits, or it will be rejected. That's why you almost always pair a Quota with a `LimitRange` (next section).

## §2 — LimitRange: defaults & per-container caps

`LimitRange` enforces per-container/min/max/default values inside one namespace.

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: team-limits
  namespace: team-alpha
spec:
  limits:
    - type: Container
      default:                # if pod doesn't set limits, use these
        cpu: 500m
        memory: 256Mi
      defaultRequest:         # if pod doesn't set requests, use these
        cpu: 100m
        memory: 64Mi
      min:
        cpu: 50m
        memory: 32Mi
      max:
        cpu: "2"
        memory: 2Gi
    - type: Pod
      max:
        cpu: "4"
        memory: 4Gi
    - type: PersistentVolumeClaim
      min: { storage: 1Gi }
      max: { storage: 20Gi }
```

```bash
oc apply -f limitrange.yaml
oc get limitrange -n team-alpha
oc describe limitrange team-limits -n team-alpha
```

LimitRange + ResourceQuota together: developers can deploy without micromanaging resources, but they can't exceed cluster limits.

## §3 — Quota scopes (advanced but on-spec)

You can scope a Quota to BestEffort vs NotBestEffort, Terminating vs NotTerminating, PriorityClass, etc.

```yaml
spec:
  scopes:
    - NotTerminating       # only long-running pods
  hard:
    pods: "10"
```

Use this to give batch/CronJobs separate accounting from web services.

## §4 — ClusterResourceQuota: a single quota across many projects

`ClusterResourceQuota` (cluster-scoped, OpenShift-only) shares quota across every namespace owned by a user/label.

```yaml
apiVersion: quota.openshift.io/v1
kind: ClusterResourceQuota
metadata:
  name: alice-everywhere
spec:
  selector:
    annotations:
      openshift.io/requester: alice         # all projects alice created
    labels: {}
  quota:
    hard:
      pods: "50"
      requests.cpu: "10"
      requests.memory: 20Gi
```

Or select by label:

```yaml
spec:
  selector:
    labels:
      matchLabels:
        team: alpha
```

Now any namespace labeled `team=alpha` rolls up against the same quota.

```bash
oc get clusterresourcequota
oc describe clusterresourcequota alice-everywhere
oc get appliedclusterresourcequota -n team-alpha
```

## §5 — Project templates

When a user runs `oc new-project`, OpenShift instantiates a built-in template. You can override it to **automatically add** a quota, LimitRange, RBAC, NetworkPolicy, etc.

### Step 1 — Get the default template

```bash
oc adm create-bootstrap-project-template -o yaml > project-template.yaml
```

### Step 2 — Edit it to add objects

Add (under `objects:`) any standard resources. Use `${PROJECT_NAME}` for the namespace.

```yaml
objects:
  # 1. Project object (already present — keep it)
  - apiVersion: project.openshift.io/v1
    kind: Project
    metadata:
      name: ${PROJECT_NAME}
      annotations:
        openshift.io/description: ${PROJECT_DESCRIPTION}
        openshift.io/display-name: ${PROJECT_DISPLAYNAME}
        openshift.io/requester: ${PROJECT_REQUESTING_USER}

  # 2. NEW: a default ResourceQuota
  - apiVersion: v1
    kind: ResourceQuota
    metadata:
      name: default-quota
      namespace: ${PROJECT_NAME}
    spec:
      hard:
        pods: "20"
        requests.cpu: "2"
        requests.memory: 4Gi
        limits.cpu: "4"
        limits.memory: 8Gi

  # 3. NEW: a default LimitRange
  - apiVersion: v1
    kind: LimitRange
    metadata:
      name: default-limits
      namespace: ${PROJECT_NAME}
    spec:
      limits:
        - type: Container
          default:        { cpu: 200m, memory: 256Mi }
          defaultRequest: { cpu: 50m,  memory: 64Mi }

  # 4. NEW: a default deny-all NetworkPolicy
  - apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: default-deny
      namespace: ${PROJECT_NAME}
    spec:
      podSelector: {}
      policyTypes: [Ingress]

  # 5. NEW: allow ingress from the router so Routes still work
  - apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: allow-from-router
      namespace: ${PROJECT_NAME}
    spec:
      podSelector: {}
      policyTypes: [Ingress]
      ingress:
        - from:
            - namespaceSelector:
                matchLabels:
                  network.openshift.io/policy-group: ingress

parameters:
  - name: PROJECT_NAME
    required: true
  - name: PROJECT_DISPLAYNAME
  - name: PROJECT_DESCRIPTION
  - name: PROJECT_ADMIN_USER
  - name: PROJECT_REQUESTING_USER
```

### Step 3 — Save it as a Template in `openshift-config`

```bash
oc apply -f project-template.yaml -n openshift-config
```

### Step 4 — Tell the cluster to use it

```yaml
# Project.config.openshift.io/cluster
apiVersion: config.openshift.io/v1
kind: Project
metadata:
  name: cluster
spec:
  projectRequestTemplate:
    name: project-request           # whatever metadata.name you gave the template
```

Or one-liner:

```bash
oc patch project.config/cluster --type=merge \
  -p '{"spec":{"projectRequestTemplate":{"name":"project-request"}}}'
```

Restart `openshift-apiserver` (or just wait — pods roll automatically):

```bash
oc rollout status -n openshift-apiserver deployment.apps/apiserver
```

### Step 5 — Verify

```bash
oc login -u alice -p alicepw
oc new-project mytest
oc get quota,limitrange,networkpolicy -n mytest
# All five objects should be present.
```

## §6 — `oc adm` helpers

```bash
# Show what a quota / LR looks like for a project
oc describe project myapp
oc describe quota -n myapp

# Force a project to honor a specific node selector for all pods
oc annotate namespace myapp 'openshift.io/node-selector=tier=worker' --overwrite
```

---

## 🧪 Labs

### Lab 7.1 — Quota that bites (25 min)

The classic gotcha: a ResourceQuota that constrains CPU/memory *requests* will **reject any pod that doesn't declare requests** — unless a LimitRange supplies defaults. This lab makes you feel that failure, then fixes it.

**Prerequisites:**
- Cluster-admin.
- Project: `oc new-project lab71`.

---

#### Step 1 — Apply a ResourceQuota (`pods=3`, `requests.cpu=500m`, `requests.memory=512Mi`)

<details>
<summary>💡 Solution</summary>

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: lab-quota
  namespace: lab71
spec:
  hard:
    pods: "3"
    requests.cpu: 500m
    requests.memory: 512Mi
```

```bash
oc apply -f quota.yaml

# Inspect — note USED vs HARD
oc get resourcequota lab-quota -n lab71
# NAME        AGE   REQUEST                                                    LIMIT
# lab-quota   5s    pods: 0/3, requests.cpu: 0/500m, requests.memory: 0/512Mi

oc describe resourcequota lab-quota -n lab71
```

**Imperative alternative:**

```bash
oc create quota lab-quota \
  --hard=pods=3,requests.cpu=500m,requests.memory=512Mi -n lab71
```

**What counting quotas track:** `pods`, `services`, `configmaps`, `secrets`, `persistentvolumeclaims`, `services.nodeports`, `services.loadbalancers`, `replicationcontrollers`. **What compute quotas track:** `requests.cpu`, `requests.memory`, `limits.cpu`, `limits.memory`, plus `requests.storage`.

</details>

---

#### Step 2 — Deploy 5 replicas of `hello-openshift` with no resource requests; watch it fail

<details>
<summary>💡 Solution</summary>

```bash
oc create deployment hello \
  --image=quay.io/openshifttest/hello-openshift:1.2.0 \
  --replicas=5 -n lab71

oc get pods -n lab71
# (Zero or very few pods appear.)

oc get deployment hello -n lab71
# NAME    READY   UP-TO-DATE   AVAILABLE
# hello   0/5     0            0
```

**Why NOTHING schedules (not even 3):** the moment a compute quota (`requests.cpu`/`requests.memory`) exists in a namespace, every new pod **must** declare those requests. `oc create deployment` produces pods with `resources: {}` — no requests — so the quota admission controller rejects *all* of them.

**See the actual rejection:**

```bash
oc get events -n lab71 --field-selector reason=FailedCreate | tail
# or look at the ReplicaSet:
oc describe rs -l app=hello -n lab71 | tail -15
# Warning  FailedCreate  ...  Error creating: pods "hello-..." is forbidden:
#   failed quota: lab-quota: must specify requests.cpu,requests.memory
```

The key phrase: **`must specify requests.cpu,requests.memory`**. This is the "quota that bites" — not a cap being hit, but pods refused for lacking requests.

</details>

---

#### Step 3 — Add a LimitRange with defaults; re-apply

<details>
<summary>💡 Solution</summary>

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: lab-limits
  namespace: lab71
spec:
  limits:
  - type: Container
    default:                 # default LIMITS if none specified
      cpu: 200m
      memory: 128Mi
    defaultRequest:          # default REQUESTS if none specified  ← this is what unblocks the quota
      cpu: 100m
      memory: 64Mi
```

```bash
oc apply -f limitrange.yaml

# Force the ReplicaSet to retry creating pods (they'll now inherit default requests)
oc rollout restart deployment/hello -n lab71
# or simply delete the stuck RS's pods / re-scale:
oc scale deployment/hello --replicas=5 -n lab71
```

**How this fixes it:** the LimitRange's `defaultRequest` is injected into any container that doesn't specify requests. Now each `hello` pod carries `requests.cpu=100m, requests.memory=64Mi`, satisfying the quota's "must specify" rule.

**LimitRange field meanings:**

| Field | Effect |
|-------|--------|
| `default` | Default *limits* applied when a container omits them |
| `defaultRequest` | Default *requests* applied when a container omits them |
| `max` | Ceiling — a container requesting more is rejected |
| `min` | Floor — a container requesting less is rejected |
| `type: Container` / `Pod` / `PersistentVolumeClaim` | What the limits apply to |

</details>

---

#### Step 4 — Confirm only 3 pods schedule and they carry the default requests

<details>
<summary>💡 Solution</summary>

```bash
oc get pods -n lab71
# NAME                     READY   STATUS    RESTARTS   AGE
# hello-xxxxx-aaaaa        1/1     Running   0          30s
# hello-xxxxx-bbbbb        1/1     Running   0          30s
# hello-xxxxx-ccccc        1/1     Running   0          30s
# (only 3 — the pods=3 cap now bites instead of the missing-requests error)

oc get deployment hello -n lab71
# READY 3/5  — two replicas can't be created

# Why only 3? Now it's the pod COUNT quota, not the requests problem:
oc describe rs -l app=hello -n lab71 | tail -5
# Warning  FailedCreate  ...  exceeded quota: lab-quota: requested: pods=1, used: pods=3, limited: pods=3

# Confirm the running pods picked up the LimitRange defaults:
oc get pod -l app=hello -n lab71 \
  -o jsonpath='{range .items[0].spec.containers[*]}{.resources.requests}{"\n"}{end}'
# {"cpu":"100m","memory":"64Mi"}
```

**The two-stage lesson:**
1. Before the LimitRange: pods rejected for *not declaring* requests (the "bite").
2. After the LimitRange: pods get defaults, so 3 schedule — then the `pods=3` count cap stops the rest.

Also check the quota usage now reflects the running pods:

```bash
oc get resourcequota lab-quota -n lab71
# pods: 3/3, requests.cpu: 300m/500m, requests.memory: 192Mi/512Mi
# (3 pods × 100m cpu = 300m; 3 × 64Mi = 192Mi)
```

**Cleanup:**

```bash
oc delete project lab71
```

</details>

---

### Lab 7.2 — ClusterResourceQuota by label (20 min)

A `ClusterResourceQuota` (CRQ, an OpenShift-specific object) enforces a shared budget *across multiple projects* selected by label or annotation. This lab uses label-based selection.

**Prerequisites:**
- Cluster-admin (CRQ is a cluster-scoped resource).

---

#### Step 1 — Create two projects both labeled `team=alpha`

<details>
<summary>💡 Solution</summary>

```bash
oc new-project team-alpha-a
oc new-project team-alpha-b

# Label the underlying namespaces
oc label namespace team-alpha-a team=alpha
oc label namespace team-alpha-b team=alpha

# Verify
oc get namespace -l team=alpha
# NAME           STATUS   AGE
# team-alpha-a   Active   30s
# team-alpha-b   Active   25s
```

**Gotcha — project vs namespace labels:** you label the **namespace** object, not the project. In OpenShift a Project is a thin wrapper over a Namespace; `oc label namespace` is the right command. `oc label project` also works (they share the label store) but namespace is the canonical target for CRQ selectors.

</details>

---

#### Step 2 — Create a ClusterResourceQuota selecting `team=alpha` with `pods: "5"`

<details>
<summary>💡 Solution</summary>

```yaml
apiVersion: quota.openshift.io/v1
kind: ClusterResourceQuota
metadata:
  name: alpha-crq
spec:
  quota:
    hard:
      pods: "5"
  selector:
    labels:
      matchLabels:
        team: alpha
```

```bash
oc apply -f crq.yaml

oc get clusterresourcequota alpha-crq
# NAME        AGE
# alpha-crq   10s

oc describe clusterresourcequota alpha-crq
# Namespace Selector: ... matchLabels team=alpha
# Resource   Used   Hard
# --------   ----   ----
# pods       0      5
```

**Two selector styles:**

```yaml
# A) Label selector (this lab)
  selector:
    labels:
      matchLabels:
        team: alpha

# B) Annotation selector — matches projects created by a specific user
  selector:
    annotations:
      openshift.io/requester: alice
```

Style B is how you build "each developer gets X across all their projects" — it keys off the `openshift.io/requester` annotation that `oc new-project` stamps on.

</details>

---

#### Step 3 — Deploy pods across both projects; confirm the shared cap of 5

<details>
<summary>💡 Solution</summary>

```bash
# 3 pods in project A
oc create deployment app-a \
  --image=quay.io/openshifttest/hello-openshift:1.2.0 \
  --replicas=3 -n team-alpha-a
oc get pods -n team-alpha-a
# 3 running

# Check the CRQ — it now shows 3/5 used, aggregated
oc describe clusterresourcequota alpha-crq
# pods   3   5

# 2 more pods in project B → total hits 5
oc create deployment app-b \
  --image=quay.io/openshifttest/hello-openshift:1.2.0 \
  --replicas=2 -n team-alpha-b
oc get pods -n team-alpha-b
# 2 running

oc describe clusterresourcequota alpha-crq
# pods   5   5     ← at the shared limit

# A 6th pod anywhere in the selected set is rejected
oc scale deployment/app-b --replicas=3 -n team-alpha-b
oc get deployment app-b -n team-alpha-b
# READY 2/3  — the 3rd can't be created

oc describe rs -l app=app-b -n team-alpha-b | tail -5
# Warning  FailedCreate  ...  exceeded quota: alpha-crq: requested: pods=1, used: pods=5, limited: pods=5
```

**The point:** the 5-pod budget is shared. It doesn't matter which of the two namespaces the pods live in — the CRQ sums usage across every namespace matching `team=alpha`.

</details>

---

#### Step 4 — Inspect the per-namespace view with `appliedclusterresourcequota`

<details>
<summary>💡 Solution</summary>

A regular user in `team-alpha-a` can't see the cluster-scoped CRQ object, but they *can* see how it applies to their namespace via the namespaced projection `AppliedClusterResourceQuota`:

```bash
oc get appliedclusterresourcequota -n team-alpha-a
# NAME        AGE
# alpha-crq   3m

oc describe appliedclusterresourcequota alpha-crq -n team-alpha-a
# Namespace:  team-alpha-a
# Resource   Used   Hard
# pods       3      5
#
# ... plus the aggregate across all matched namespaces
```

**Why this exists:** developers need visibility into a quota that spans namespaces they may not all have access to. `AppliedClusterResourceQuota` is the read-only, namespace-scoped window into the shared CRQ. On the exam, if a task says "as the developer, show the quota", this is the object to use — not `clusterresourcequota` (which needs cluster-level read).

**Cleanup:**

```bash
oc delete clusterresourcequota alpha-crq
oc delete project team-alpha-a team-alpha-b
```

</details>

---

### Lab 7.3 — Custom project template (35 min)

The capstone self-service task: make **every new project** automatically ship with a quota, limit range, and locked-down NetworkPolicies. This is a very common exam requirement.

**Prerequisites:**
- Cluster-admin.
- At least one non-admin user to test with (e.g. `alice` from the Objective 4 labs, or create one).

---

#### Step 1 — Generate the bootstrap template; add Quota + LimitRange + two NetworkPolicies

<details>
<summary>💡 Solution</summary>

```bash
# Generate the default project-request template as a starting point
oc adm create-bootstrap-project-template -o yaml > project-template.yaml
```

The generated file has a `Template` with an `objects:` list (Project, RoleBinding) and a `parameters:` list (including `${PROJECT_NAME}`). Add your four objects into the `objects:` array. Full edited template:

```yaml
apiVersion: template.openshift.io/v1
kind: Template
metadata:
  name: project-request
objects:
- apiVersion: project.openshift.io/v1
  kind: Project
  metadata:
    name: ${PROJECT_NAME}
    annotations:
      openshift.io/description: ${PROJECT_DESCRIPTION}
      openshift.io/display-name: ${PROJECT_DISPLAYNAME}
      openshift.io/requester: ${PROJECT_REQUESTING_USER}
- apiVersion: rbac.authorization.k8s.io/v1
  kind: RoleBinding
  metadata:
    name: admin
    namespace: ${PROJECT_NAME}
  roleRef:
    apiGroup: rbac.authorization.k8s.io
    kind: ClusterRole
    name: admin
  subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: ${PROJECT_ADMIN_USER}
# ---- added objects ----
- apiVersion: v1
  kind: ResourceQuota
  metadata:
    name: default-quota
    namespace: ${PROJECT_NAME}
  spec:
    hard:
      pods: "10"
      requests.cpu: "2"
      requests.memory: 4Gi
      limits.cpu: "4"
      limits.memory: 8Gi
- apiVersion: v1
  kind: LimitRange
  metadata:
    name: default-limits
    namespace: ${PROJECT_NAME}
  spec:
    limits:
    - type: Container
      default:
        cpu: 500m
        memory: 512Mi
      defaultRequest:
        cpu: 100m
        memory: 128Mi
- apiVersion: networking.k8s.io/v1
  kind: NetworkPolicy
  metadata:
    name: deny-all-ingress
    namespace: ${PROJECT_NAME}
  spec:
    podSelector: {}
    policyTypes: [Ingress]
- apiVersion: networking.k8s.io/v1
  kind: NetworkPolicy
  metadata:
    name: allow-from-router
    namespace: ${PROJECT_NAME}
  spec:
    podSelector: {}
    policyTypes: [Ingress]
    ingress:
    - from:
      - namespaceSelector:
          matchLabels:
            network.openshift.io/policy-group: ingress
parameters:
- name: PROJECT_NAME
- name: PROJECT_DISPLAYNAME
- name: PROJECT_DESCRIPTION
- name: PROJECT_ADMIN_USER
- name: PROJECT_REQUESTING_USER
```

**Order matters for NetworkPolicies:** `deny-all-ingress` establishes the baseline (nothing gets in), then `allow-from-router` re-opens ingress from the OpenShift router only. Together: pods are reachable via Routes/Services through the router, but not directly from other namespaces.

</details>

---

#### Step 2 — Save the template as `project-request` in `openshift-config`

<details>
<summary>💡 Solution</summary>

```bash
oc create -f project-template.yaml -n openshift-config
# template.template.openshift.io/project-request created

# Verify
oc get template project-request -n openshift-config
```

**Gotcha — namespace and name:** the template MUST live in `openshift-config` (where the OAuth/project config can read it). The name (`project-request` here) is arbitrary but must match what you reference in Step 3. If you re-run and it already exists, use `oc replace -f ... ` or delete first.

</details>

---

#### Step 3 — Patch `project.config/cluster` to use the template

<details>
<summary>💡 Solution</summary>

```bash
oc patch project.config.openshift.io/cluster --type=merge -p='
spec:
  projectRequestTemplate:
    name: project-request
'
```

**Verify the config points at your template:**

```bash
oc get project.config.openshift.io/cluster -o jsonpath='{.spec.projectRequestTemplate.name}{"\n"}'
# project-request
```

**Critical — wait for the apiserver to roll out.** The `openshift-apiserver` pods must restart to pick up the new template. New-project requests use the OLD behavior until this completes:

```bash
oc rollout status -n openshift-apiserver deployment/apiserver --timeout=5m
# or watch:
oc get pods -n openshift-apiserver -w
```

This typically takes 1–3 minutes. If you test too early, your extra objects won't appear and you'll think the template is broken.

</details>

---

#### Step 4 — As a regular user, create a project and verify the four extra objects

<details>
<summary>💡 Solution</summary>

```bash
# As a non-admin (e.g. alice)
oc login -u alice -p <password>
oc new-project demo
# Now using project "demo" ...

# Check all four injected objects exist
oc get resourcequota,limitrange,networkpolicy -n demo
# NAME                             ...
# resourcequota/default-quota      pods: 0/10, ...
# limitrange/default-limits        Container ...
# networkpolicy.networking.k8s.io/deny-all-ingress
# networkpolicy.networking.k8s.io/allow-from-router
```

All four present ⇒ the template works. If they're missing:
1. The apiserver rollout (Step 3) hasn't finished — wait and create another test project.
2. The template YAML has a syntax error — check `oc get events -n openshift-apiserver` and validate the template.
3. Wrong template name in the project config patch.

</details>

---

#### Step 5 — Deploy an app and reach it via a Route; confirm quota + router-allow both work

<details>
<summary>💡 Solution</summary>

```bash
# Still as alice, in project demo
oc create deployment web \
  --image=quay.io/openshifttest/hello-openshift:1.2.0 -n demo
oc expose deployment web --port=8080 -n demo
oc expose service web -n demo          # creates a Route

# The pod picked up default requests from the LimitRange (proving LR works):
oc get pod -l app=web -n demo \
  -o jsonpath='{.items[0].spec.containers[0].resources.requests}{"\n"}'
# {"cpu":"100m","memory":"128Mi"}

# The Route works THROUGH the router (proving allow-from-router NetworkPolicy works
# despite the deny-all baseline):
ROUTE=$(oc get route web -n demo -o jsonpath='{.spec.host}')
curl -I http://$ROUTE
# HTTP/1.1 200 OK

# Prove the deny-all baseline blocks direct cross-namespace access:
oc run probe --image=registry.access.redhat.com/ubi9/ubi-minimal:latest \
  -n default --rm -it --restart=Never -- \
  curl -m 5 http://web.demo.svc.cluster.local:8080
# Times out — direct pod-to-pod from another namespace is blocked by deny-all-ingress
```

**What each result proves:**
- Route returns 200 → `allow-from-router` NetworkPolicy correctly permits router traffic.
- Cross-namespace curl times out → `deny-all-ingress` correctly blocks everything else.
- Pod has default requests → LimitRange injection works.
- (If you scale past 10 pods, the ResourceQuota would cap it → quota works.)

**Cleanup:**

```bash
# As admin — reset the project config so later labs get default behavior
oc patch project.config.openshift.io/cluster --type=json \
  -p='[{"op":"remove","path":"/spec/projectRequestTemplate"}]'
oc delete template project-request -n openshift-config
oc delete project demo
oc rollout status -n openshift-apiserver deployment/apiserver --timeout=5m
```

</details>

---

### Lab 7.4 — Hard block: ban NodePort for devs (15 min)

A focused quota trick: setting `services.nodeports: "0"` prevents developers from exposing services on node ports (a common security requirement), while ClusterIP services keep working.

**Prerequisites:**
- Project: `oc new-project lab74`.

---

#### Step 1 — Apply a Quota with `services.nodeports: "0"`

<details>
<summary>💡 Solution</summary>

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: no-nodeports
  namespace: lab74
spec:
  hard:
    services.nodeports: "0"
    services.loadbalancers: "0"    # bonus: also ban LoadBalancer services
```

```bash
oc apply -f no-nodeports.yaml

oc get resourcequota no-nodeports -n lab74
# NAME           AGE   REQUEST
# no-nodeports   5s    services.loadbalancers: 0/0, services.nodeports: 0/0
```

**Imperative form:**

```bash
oc create quota no-nodeports \
  --hard=services.nodeports=0,services.loadbalancers=0 -n lab74
```

**Why this works:** ResourceQuota can count specific *sub-types* of services. Setting the hard limit to 0 means "zero NodePort services allowed" — any attempt to create one exceeds the quota immediately.

</details>

---

#### Step 2 — Try to expose a NodePort service (should be rejected)

<details>
<summary>💡 Solution</summary>

```bash
# First deploy something to expose
oc create deployment hello \
  --image=quay.io/openshifttest/hello-openshift:1.2.0 -n lab74

# Attempt a NodePort service
oc expose deployment hello --type=NodePort --port=8080 -n lab74
# Error from server (Forbidden): services "hello" is forbidden:
#   exceeded quota: no-nodeports, requested: services.nodeports=1,
#   used: services.nodeports=0, limited: services.nodeports=0
```

Rejected at admission. The quota controller sees the request would push `services.nodeports` from 0 to 1, which exceeds the hard limit of 0.

**Same for LoadBalancer (if you added that line):**

```bash
oc expose deployment hello --type=LoadBalancer --port=8080 -n lab74
# Error ... exceeded quota: no-nodeports ... services.loadbalancers=0
```

</details>

---

#### Step 3 — Confirm ClusterIP still works

<details>
<summary>💡 Solution</summary>

```bash
# ClusterIP is the default type — not counted by services.nodeports
oc expose deployment hello --port=8080 -n lab74
# service/hello exposed

oc get svc hello -n lab74
# NAME    TYPE        CLUSTER-IP       PORT(S)
# hello   ClusterIP   172.30.x.x       8080/TCP

# The quota is unaffected — ClusterIP services don't count against nodeports:
oc get resourcequota no-nodeports -n lab74
# services.nodeports: 0/0   (still 0 used)
```

**The design pattern:** force developers to expose apps the "OpenShift way" — via Routes on top of ClusterIP services, which go through the managed router — rather than punching holes directly on node ports. NodePort/LoadBalancer bypass the router's TLS, hostname routing, and access controls, so banning them is a common hardening step.

**How devs should expose apps instead:**

```bash
oc expose deployment hello --port=8080 -n lab74      # ClusterIP service
oc expose service hello -n lab74                      # Route → reachable externally via the router
oc get route hello -n lab74
```

**Cleanup:**

```bash
oc delete project lab74
```

</details>

---

---

## ⚡ Drills (timed, no docs)

| Drill | Target time |
|-------|-------------|
| Apply a ResourceQuota capping pods=10, cpu=2 | 60 s |
| Apply a LimitRange with default 100m/64Mi requests | 60 s |
| Create a ClusterResourceQuota by user annotation | 90 s |
| Modify the project template to add a default NetworkPolicy | 4 min |
| Find which Quota a namespace is using | 30 s |
| Identify why a pod is `Pending` because of `ResourceQuota` | 60 s |

---

## ❗ Common pitfalls

1. **Quota set, no LimitRange → all new pods rejected** until they declare requests/limits.
2. **The project template MUST live in `openshift-config`**, not elsewhere.
3. **`projectRequestTemplate.name` references metadata.name** of the Template, not the file.
4. **Changes to the project template only affect *future* `oc new-project` calls** — existing namespaces are not retro-fitted.
5. **`ClusterResourceQuota` uses an OpenShift API group** (`quota.openshift.io`), not core Kubernetes.

## 🔗 Docs to bookmark

- Quotas: https://docs.openshift.com/container-platform/4.18/applications/quotas/quotas-setting-per-project.html
- ClusterResourceQuota: https://docs.openshift.com/container-platform/4.18/applications/quotas/setting-quotas-across-multiple-projects.html
- LimitRanges: https://docs.openshift.com/container-platform/4.18/nodes/clusters/setting-limit-ranges.html
- Project templates: https://docs.openshift.com/container-platform/4.18/applications/projects/configuring-project-creation.html
