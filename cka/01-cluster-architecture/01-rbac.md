# 1.1 — Manage Role-Based Access Control (RBAC)

> **Objective:** Manage role based access control (RBAC).
> **Exam frequency:** Very high. Expect 1–2 RBAC tasks.

## 🎯 Why this matters

RBAC controls **who can do what** in the cluster. Every K8s admin task that involves a ServiceAccount, kubeconfig, or "permission denied" error routes through RBAC.

## 🧠 Core concepts

K8s RBAC has 4 objects:

| Object | Scope | What it does |
| --- | --- | --- |
| `Role` | Namespaced | Defines a set of permissions *in one namespace* |
| `ClusterRole` | Cluster-wide | Defines permissions cluster-wide or for non-namespaced resources (nodes, PVs) |
| `RoleBinding` | Namespaced | Binds a Role (or ClusterRole) to subjects, scoped to one namespace |
| `ClusterRoleBinding` | Cluster-wide | Binds a ClusterRole to subjects cluster-wide |

**Subjects** can be: `User`, `Group`, or `ServiceAccount`.

### The mental model

```
                  +-------------+
                  | RoleBinding |---→ binds subject ──→ Role / ClusterRole
                  +-------------+
                          │
                          └─→ scoped to a namespace

  +--------------------+
  | ClusterRoleBinding |───→ binds subject ──→ ClusterRole
  +--------------------+
                     │
                     └─→ cluster-wide
```

A `RoleBinding` **can reference a `ClusterRole`** — this is how you reuse one definition across multiple namespaces.

### `verbs`, `resources`, `apiGroups`

A rule says: "subjects can perform these **verbs** on these **resources** in these **apiGroups**."

```yaml
rules:
- apiGroups: [""]            # "" = core API group (pods, services, etc.)
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["*"]
```

Common verbs: `get`, `list`, `watch`, `create`, `update`, `patch`, `delete`, `deletecollection`. `*` = all.

Common apiGroups:
- `""` (empty) → core: pods, services, configmaps, secrets, nodes, namespaces, pv, pvc
- `apps` → deployments, statefulsets, daemonsets, replicasets
- `batch` → jobs, cronjobs
- `networking.k8s.io` → ingresses, networkpolicies
- `rbac.authorization.k8s.io` → roles, rolebindings, clusterroles, clusterrolebindings
- `gateway.networking.k8s.io` → gateways, httproutes (new for v1.35)

## 🛠️ Hands-on commands

### Create a ServiceAccount

```bash
k create serviceaccount dev-sa -n dev
# or YAML:
cat <<EOF | k apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: dev-sa
  namespace: dev
EOF
```

### Create a Role (imperative)

```bash
k create role pod-reader \
  --verb=get,list,watch \
  --resource=pods \
  -n dev

# Inspect it:
k get role pod-reader -n dev -o yaml
```

### Create a RoleBinding

```bash
k create rolebinding dev-sa-pod-reader \
  --role=pod-reader \
  --serviceaccount=dev:dev-sa \
  -n dev
```

For a user instead of SA: `--user=alice` (or `--group=devs`).

### Create a ClusterRole

```bash
k create clusterrole node-reader \
  --verb=get,list,watch \
  --resource=nodes
```

### Create a ClusterRoleBinding

```bash
k create clusterrolebinding cluster-admin-alice \
  --clusterrole=cluster-admin \
  --user=alice
```

### Verify permissions — the killer command

```bash
# Can I do X?
k auth can-i create pods --namespace=dev
# yes / no

# As another user:
k auth can-i create pods --as=alice --namespace=dev

# As a service account:
k auth can-i list pods \
  --as=system:serviceaccount:dev:dev-sa \
  --namespace=dev
```

**`kubectl auth can-i`** is the fastest verifier on the exam. Use it every time.

### Aggregate ClusterRoles (advanced but seen on exam)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: monitoring
  labels:
    rbac.example.com/aggregate-to-admin: "true"
rules:
- apiGroups: ["monitoring.coreos.com"]
  resources: ["*"]
  verbs: ["*"]
```

A ClusterRole with `aggregationRule` automatically absorbs rules from any ClusterRole matching the label selector.

## 📄 Full YAML examples

### Read-only namespace access

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: dev-viewer
  namespace: dev
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: dev-viewer-binding
  namespace: dev
subjects:
- kind: User
  name: alice
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: dev-viewer
  apiGroup: rbac.authorization.k8s.io
```

### ServiceAccount that can manage Deployments in one namespace

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: deployer
  namespace: app
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: deployment-manager
  namespace: app
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["*"]
- apiGroups: [""]
  resources: ["pods", "services"]
  verbs: ["get", "list", "watch", "create", "update", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: deployer-binding
  namespace: app
subjects:
- kind: ServiceAccount
  name: deployer
  namespace: app
roleRef:
  kind: Role
  name: deployment-manager
  apiGroup: rbac.authorization.k8s.io
```

## 🏋️ Exam-style exercises

> Try each WITHOUT docs first. If stuck >5 min, peek at the answer.

### Exercise 1
Create a namespace `team-a`. Create a ServiceAccount `ci-bot` in that namespace. Give `ci-bot` permission to **create and list Deployments** in `team-a` only. Verify with `kubectl auth can-i`.

<details><summary>Solution</summary>

```bash
k create namespace team-a
k create serviceaccount ci-bot -n team-a
k create role deploy-manager --verb=create,list --resource=deployments -n team-a
k create rolebinding ci-bot-deploy --role=deploy-manager --serviceaccount=team-a:ci-bot -n team-a

k auth can-i create deployments --as=system:serviceaccount:team-a:ci-bot -n team-a
# yes
k auth can-i create deployments --as=system:serviceaccount:team-a:ci-bot -n default
# no
```
</details>

### Exercise 2
Create a user `auditor` who can **list pods in every namespace** but cannot do anything else.

<details><summary>Solution</summary>

Needs a **ClusterRole** (because cross-namespace) bound via **ClusterRoleBinding**.

```bash
k create clusterrole pod-lister --verb=list --resource=pods
k create clusterrolebinding auditor-binding --clusterrole=pod-lister --user=auditor

k auth can-i list pods --as=auditor --all-namespaces  # yes
k auth can-i delete pods --as=auditor                 # no
```
</details>

### Exercise 3
A user `dba` should be able to manage **Secrets and ConfigMaps in namespaces `db-prod` and `db-staging`** but nothing else. Use the same Role definition in both namespaces.

<details><summary>Solution</summary>

Define a **ClusterRole** (so it's reusable), then **two RoleBindings** (one per namespace) pointing to that ClusterRole.

```bash
k create clusterrole config-manager \
  --verb=get,list,watch,create,update,patch,delete \
  --resource=secrets,configmaps

k create rolebinding dba-db-prod \
  --clusterrole=config-manager --user=dba -n db-prod
k create rolebinding dba-db-staging \
  --clusterrole=config-manager --user=dba -n db-staging
```
</details>

### Exercise 4
Inspect what permissions the default `system:masters` group has.

<details><summary>Solution</summary>

```bash
k get clusterrolebindings -o wide | grep system:masters
# Find that system:masters is bound to cluster-admin
k describe clusterrole cluster-admin
# Shows * verbs on * resources on * apiGroups → god mode
```
</details>

### Exercise 5
Generate a kubeconfig for the ServiceAccount `ci-bot` from Exercise 1, so it can be used outside the cluster.

<details><summary>Solution</summary>

In K8s ≥ 1.24, SA tokens are not auto-generated. Create a token explicitly:

```bash
# Short-lived token (recommended)
TOKEN=$(k create token ci-bot -n team-a --duration=24h)

# Or persistent token via Secret:
cat <<EOF | k apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ci-bot-token
  namespace: team-a
  annotations:
    kubernetes.io/service-account.name: ci-bot
type: kubernetes.io/service-account-token
EOF
TOKEN=$(k get secret ci-bot-token -n team-a -o jsonpath='{.data.token}' | base64 -d)

# Build kubeconfig:
k config set-cluster cka --server=https://<api>:6443 --certificate-authority=/etc/kubernetes/pki/ca.crt --kubeconfig=ci-bot.kubeconfig
k config set-credentials ci-bot --token=$TOKEN --kubeconfig=ci-bot.kubeconfig
k config set-context ci-bot@cka --cluster=cka --user=ci-bot --namespace=team-a --kubeconfig=ci-bot.kubeconfig
k config use-context ci-bot@cka --kubeconfig=ci-bot.kubeconfig

# Test:
k --kubeconfig=ci-bot.kubeconfig get pods
```
</details>

## ⚠️ Common pitfalls

- **Forgetting the namespace flag** when binding a Role. Roles and RoleBindings are namespaced.
- **Using a `Role` for a cluster-scoped resource** like `nodes` or `persistentvolumes`. Won't work — must be `ClusterRole`.
- **Wrong subject syntax for SA.** It's `system:serviceaccount:<ns>:<name>`, not just the SA name.
- **Verbs typos.** Common: `get`, `list`, `watch`, `create`, `update`, `patch`, `delete`. `read` is NOT a verb.
- **Resources are plural and lowercase.** `pods` not `Pod`. `persistentvolumeclaims` not `PVC`.
- **Adding a permission to an existing Role** — `k edit role X` and add to `rules` array. Don't create a new Role.

## 📚 Doc bookmarks (pre-open in exam browser)

- [Using RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) — the canonical reference
- [Authenticating](https://kubernetes.io/docs/reference/access-authn-authz/authentication/) — for users and SAs
- [kubectl auth](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#auth) — the verifier

## 🔁 Speed drills (do daily for a week)

1. Create namespace + SA + Role + RoleBinding granting "list pods" — **target: 60s**
2. Verify with `kubectl auth can-i` — **target: 10s**
3. Same but with a ClusterRole bound via RoleBinding to a specific namespace — **target: 90s**
