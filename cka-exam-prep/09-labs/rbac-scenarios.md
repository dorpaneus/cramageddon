# RBAC Lab — 10 Practical Scenarios

> **Time per scenario:** 5–10 min
> **Goal:** Build muscle memory for RBAC. RBAC is on every CKA exam.
> Run in any cluster; create namespaces as needed. Verify every task with `kubectl auth can-i`.

> Setup once:
> ```bash
> alias k=kubectl
> export do='--dry-run=client -o yaml'
> ```

---

## Scenario 1 — Read-only namespace access

> Create namespace `view-test`. Create a ServiceAccount `viewer` in it. Grant it permissions to **only** get/list/watch pods, services, and deployments in that namespace. Verify.

<details><summary>Solution</summary>

```bash
k create ns view-test
k create sa viewer -n view-test

k create role read-only -n view-test \
  --verb=get,list,watch \
  --resource=pods,services,deployments

k create rolebinding viewer-rb -n view-test \
  --role=read-only \
  --serviceaccount=view-test:viewer

# Verify:
k auth can-i list pods -n view-test --as=system:serviceaccount:view-test:viewer       # yes
k auth can-i delete pods -n view-test --as=system:serviceaccount:view-test:viewer     # no
k auth can-i list pods -n default --as=system:serviceaccount:view-test:viewer         # no
```
</details>

---

## Scenario 2 — Cluster-wide node reader

> Grant user `monitoring-bot` permission to **list and watch** all nodes (cluster-scoped). Nothing else.

<details><summary>Solution</summary>

```bash
k create clusterrole node-reader --verb=list,watch --resource=nodes
k create clusterrolebinding monitoring-nodes \
  --clusterrole=node-reader \
  --user=monitoring-bot

k auth can-i list nodes --as=monitoring-bot           # yes
k auth can-i delete nodes --as=monitoring-bot         # no
k auth can-i list pods --as=monitoring-bot            # no
```
</details>

---

## Scenario 3 — Pod logs without exec

> Create a SA `log-reader` in namespace `prod`. Allow it to **read pod logs** but not exec into pods. Verify both.

<details><summary>Solution</summary>

```bash
k create ns prod
k create sa log-reader -n prod

k create role log-only -n prod \
  --verb=get,list \
  --resource=pods,pods/log

k create rolebinding log-reader-rb -n prod \
  --role=log-only \
  --serviceaccount=prod:log-reader

k auth can-i get pods/log -n prod --as=system:serviceaccount:prod:log-reader   # yes
k auth can-i create pods/exec -n prod --as=system:serviceaccount:prod:log-reader  # no
```

Note: `pods/log` and `pods/exec` are **subresources** — each is a distinct resource for RBAC. Naming them explicitly is required; you can't shortcut via `pods`.
</details>

---

## Scenario 4 — Multi-namespace access via ClusterRole + RoleBindings

> User `dev-lead` should have full Deployment/ReplicaSet access in **both** namespaces `dev` and `staging`. Use one ClusterRole bound twice.

<details><summary>Solution</summary>

```bash
k create ns dev staging
k create clusterrole deploy-admin \
  --verb=get,list,watch,create,update,patch,delete \
  --resource=deployments,replicasets

k create rolebinding dev-lead-dev -n dev \
  --clusterrole=deploy-admin --user=dev-lead

k create rolebinding dev-lead-staging -n staging \
  --clusterrole=deploy-admin --user=dev-lead

k auth can-i create deployments -n dev --as=dev-lead       # yes
k auth can-i create deployments -n staging --as=dev-lead   # yes
k auth can-i create deployments -n prod --as=dev-lead      # no
```

**Why ClusterRole + RoleBinding (not Role × 2)?** Same rules, no duplication. The RoleBinding scopes them to a namespace.
</details>

---

## Scenario 5 — Specific resource by name

> Allow user `release-bot` to update **only** the Deployment named `web` in namespace `prod`. No other Deployment.

<details><summary>Solution</summary>

Use `resourceNames` to scope a Role:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: update-web, namespace: prod }
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get","update","patch"]
  resourceNames: ["web"]
```

```bash
k apply -f role.yaml
k create rolebinding release-bot-rb -n prod \
  --role=update-web --user=release-bot

k auth can-i patch deployment/web -n prod --as=release-bot         # yes
k auth can-i patch deployment/api -n prod --as=release-bot         # no
```

Caveat: `list` and `create` cannot use `resourceNames` (you don't know the name at list/create time). Tasks that need `list` of `web` only must filter client-side.
</details>

---

## Scenario 6 — Aggregated ClusterRole (read-only union)

> Create a ClusterRole `team-read` that aggregates two ClusterRoles tagged `team-read-aggregate: "true"`. Then create two ClusterRoles with that label, each granting read on different resources.

<details><summary>Solution</summary>

```yaml
# Aggregating ClusterRole — empty rules; controller fills them in:
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata: { name: team-read }
aggregationRule:
  clusterRoleSelectors:
  - matchLabels:
      team-read-aggregate: "true"
rules: []
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: read-pods
  labels:
    team-read-aggregate: "true"
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get","list","watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: read-services
  labels:
    team-read-aggregate: "true"
rules:
- apiGroups: [""]
  resources: ["services"]
  verbs: ["get","list","watch"]
```

```bash
k apply -f aggregate.yaml
k describe clusterrole team-read    # should show combined rules
```
</details>

---

## Scenario 7 — Disable default ServiceAccount auto-mount

> Pods in namespace `secure` should **not** get a token mounted automatically.

<details><summary>Solution</summary>

Two options:

```bash
# Option A — disable on the SA:
k -n secure patch sa default -p '{"automountServiceAccountToken":false}'

# Option B — disable on each pod (overrides SA):
# spec:
#   automountServiceAccountToken: false
```

Verify by exec'ing into a new pod and listing `/var/run/secrets/kubernetes.io/serviceaccount/` — it should be empty.
</details>

---

## Scenario 8 — Audit who can do what

> List **all** RoleBindings in cluster that reference the ClusterRole `cluster-admin`.

<details><summary>Solution</summary>

```bash
# ClusterRoleBindings referencing cluster-admin:
k get clusterrolebindings -o json | \
  jq -r '.items[] | select(.roleRef.name=="cluster-admin") | .metadata.name'

# Without jq:
k get clusterrolebindings -o jsonpath='{range .items[?(@.roleRef.name=="cluster-admin")]}{.metadata.name}{"\n"}{end}'

# All RoleBindings (namespaced) referencing cluster-admin:
k get rolebindings -A -o jsonpath='{range .items[?(@.roleRef.name=="cluster-admin")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}'
```
</details>

---

## Scenario 9 — Group-based RBAC

> Grant **anyone** in the OIDC group `platform-engineers` cluster-admin equivalent on namespace `platform`.

<details><summary>Solution</summary>

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: platform-eng-admins, namespace: platform }
subjects:
- kind: Group
  name: platform-engineers
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: admin                       # built-in: admin in a single namespace
  apiGroup: rbac.authorization.k8s.io
```

`admin` is one of the pre-existing ClusterRoles (`view`, `edit`, `admin`, `cluster-admin`). Inspect:

```bash
k get clusterroles | grep -E '^(view|edit|admin|cluster-admin)\s'
k describe clusterrole admin | head -30
```
</details>

---

## Scenario 10 — Service account token for an external system

> Create a non-expiring projected token? **No — that's deprecated.** Instead, create a ServiceAccount token Secret (legacy long-lived) when truly needed. Otherwise, use `kubectl create token`.

<details><summary>Solution</summary>

Modern approach (preferred — short-lived):
```bash
k create sa ci -n cicd
k create token ci -n cicd --duration=8760h     # max usually 1 year; cluster-configurable
# Output: a JWT to use in API calls or kubeconfig
```

Legacy long-lived token (Kubernetes 1.24+ requires explicit annotation):
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ci-token
  namespace: cicd
  annotations:
    kubernetes.io/service-account.name: ci
type: kubernetes.io/service-account-token
```

```bash
k apply -f token-secret.yaml
k -n cicd get secret ci-token -o jsonpath='{.data.token}' | base64 -d
```

⚠️ Long-lived tokens are a security risk. Prefer `kubectl create token` (TokenRequest API) whenever possible.
</details>

---

## Bonus drills

```bash
# What CAN I do as the default SA in default namespace?
k auth can-i --list --as=system:serviceaccount:default:default

# What CAN this user do?
k auth can-i --list --as=jane -n prod

# Imitation testing:
k get pods --as=system:serviceaccount:dev:pipeline -n dev
k create deploy test --image=nginx --as=jane -n prod
```

---

## RBAC mental checklist

1. **Role vs ClusterRole** — namespaced vs cluster-scoped resources.
2. **RoleBinding** binds either Role or ClusterRole → scoped to its namespace.
3. **ClusterRoleBinding** binds ClusterRole → cluster-wide.
4. **`resourceNames`** narrows to specific objects (but blocks `list`/`create`).
5. **Subresources** like `pods/log`, `pods/exec` are separate resources.
6. **Verbs**: `get,list,watch,create,update,patch,delete,deletecollection` and the special verbs (`impersonate`, `bind`, `escalate`).
7. **API groups**: core = `""`, others like `"apps"`, `"batch"`, `"networking.k8s.io"`. List with `k api-resources`.
8. **Always verify** with `auth can-i`.

---

## Doc bookmarks

- https://kubernetes.io/docs/reference/access-authn-authz/rbac/
- https://kubernetes.io/docs/reference/access-authn-authz/authorization/
- https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/
