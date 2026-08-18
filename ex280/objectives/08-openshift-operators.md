# Objective 8 - Manage OpenShift Operators

> **Exam study points:**
> - Install an operator
> - Uninstall an operator
> - Delete an operator

In OCP 4.18, almost every cluster service (logging, monitoring, GitOps, Pipelines, Service Mesh, Cert Manager, Quay…) is delivered as an **Operator**, managed by the **Operator Lifecycle Manager (OLM)**.

## §1 - OLM mental model

```
[OperatorHub catalog]                    ← CatalogSource (catalog of packaged operators)
        │
        ▼  Subscription says "I want operator X from channel Y"
[Subscription]
        │
        ▼  OLM creates / updates
[InstallPlan]                            ← lists the CSVs (versions) about to install
        │
        ▼  Approved automatically (or manually)
[ClusterServiceVersion (CSV)]            ← the actual installed operator version
        │
        ▼  CSV creates
[Deployment for the operator]            ← the pod that does the work
        │
        ▼  Operator pod watches
[Custom Resources (CRs)]                 ← e.g. Kafka, ArgoCD, Quay…
```

Each layer is its own Kubernetes resource - you can `oc get` them all:

```bash
oc get catalogsources -n openshift-marketplace
oc get packagemanifests | head
oc get operatorgroups -A
oc get subscriptions -A
oc get installplans -A
oc get csv -A
```

## §2 - Where operators get scoped

Two kinds of `OperatorGroup`:

| Mode | Target namespace(s) |
|------|----------------------|
| **AllNamespaces** | The operator watches all namespaces. Operator pod lives in `openshift-operators` (which already has a built-in AllNamespaces group). |
| **OwnNamespace / SingleNamespace** | Operator watches only one (or a list). You create a dedicated namespace + OperatorGroup. |

> Some operators only support one mode (the CSV declares supported modes). The web console enforces this; the CLI doesn't - be careful.

## §3 - Install an operator (Console)

The fast path on exam day if available:

1. Web console → **Operators → OperatorHub**.
2. Search the operator (e.g. *Web Terminal*).
3. Click **Install**.
4. Pick:
   - **Update channel** (e.g. `stable`)
   - **Installation mode** (AllNamespaces or a specific one)
   - **Approval strategy** (Automatic / Manual)
5. Wait for `Succeeded` on the CSV.

## §4 - Install an operator (CLI)

The exam may force CLI. Three resources:

```yaml
# 1. (Skip this if installing into openshift-operators — already exists)
apiVersion: v1
kind: Namespace
metadata:
  name: my-op
---
# 2. OperatorGroup (skip if AllNamespaces in openshift-operators)
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: my-op-group
  namespace: my-op
spec:
  targetNamespaces:
    - my-op             # own-namespace mode
---
# 3. Subscription — this triggers the install
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: web-terminal
  namespace: openshift-operators              # for AllNamespaces operators
spec:
  channel: fast
  name: web-terminal
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic              # or Manual
```

Apply and watch:

```bash
oc apply -f subscription.yaml

oc get sub -n openshift-operators
oc get installplan -n openshift-operators
oc get csv -n openshift-operators
oc get csv -n openshift-operators -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}'
```

You're done when the CSV is `Succeeded`.

### Finding the right Subscription values

```bash
# All available operators on the cluster
oc get packagemanifests -n openshift-marketplace

# Show channels and default channel for one operator
oc get packagemanifest web-terminal -n openshift-marketplace -o yaml | less
```

Pull `channel`, `name`, `source`, `sourceNamespace` from there.

### Manual approval workflow

```yaml
installPlanApproval: Manual
```

OLM creates an InstallPlan but waits for approval:

```bash
oc get installplan -n my-op
oc patch installplan install-xxxx -n my-op --type=merge -p '{"spec":{"approved":true}}'
```

This is also how you control **operator upgrades** - same flow, but for the next CSV.

## §5 - Uninstall / delete an operator

Two stages:

### Stage A - Uninstall (stop OLM from re-installing it)

```bash
# 1. Delete the Subscription
oc delete subscription web-terminal -n openshift-operators

# 2. Delete the CSV (this stops & removes the operator's Deployment)
oc get csv -n openshift-operators | grep web-terminal
oc delete csv web-terminal.v1.x.y -n openshift-operators
```

### Stage B - Clean up CRs, CRDs, OperatorGroup, namespace

```bash
# Delete any Custom Resources you created (e.g. WebTerminal instances)
oc get crd | grep web-terminal
oc delete crd <name>                  # ⚠ cluster-wide; will cascade-delete CRs

# If you used a dedicated namespace:
oc delete operatorgroup -n my-op --all
oc delete namespace my-op
```

> ⚠️ **The web console "Uninstall" button only does Stage A** - CRDs and CRs stick around. On the exam, *fully* delete unless the prompt says otherwise.

## §6 - Updating an operator

Two ways:

```bash
# 1. Change channel (rare, e.g. stable-4.18 → fast-4.18)
oc patch subscription web-terminal -n openshift-operators --type=merge \
  -p '{"spec":{"channel":"stable"}}'

# 2. Approve a pending InstallPlan (Manual approval mode)
oc get ip -n openshift-operators
oc patch installplan <name> -n openshift-operators --type=merge -p '{"spec":{"approved":true}}'

# Watch the new CSV come up & old one go away
oc get csv -n openshift-operators -w
```

## §7 - Catalog sources (where operators come from)

Default catalogs in 4.18:

| CatalogSource | Description |
|---------------|-------------|
| `redhat-operators` | Red Hat-supported operators |
| `certified-operators` | ISV-certified (Red Hat partners) |
| `community-operators` | Community-supported (no SLA) |
| `redhat-marketplace` | Paid marketplace offerings |

```bash
oc get catsrc -n openshift-marketplace
```

You can **disable** community/marketplace if your security policy forbids them:

```yaml
apiVersion: config.openshift.io/v1
kind: OperatorHub
metadata: { name: cluster }
spec:
  sources:
    - name: community-operators
      disabled: true
```

## §8 - A concrete example: install OpenShift Pipelines (Tekton)

```yaml
# subscription-pipelines.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-pipelines-operator
  namespace: openshift-operators
spec:
  channel: latest
  name: openshift-pipelines-operator-rh
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
```

```bash
oc apply -f subscription-pipelines.yaml
oc get csv -n openshift-operators -w        # wait for Succeeded
oc get pods -n openshift-pipelines          # operator-installed namespace
```

## 🧪 Labs

### Lab 8.1 — Install via Console (15 min)

The console install path is the easiest, but you must understand the three choices it asks you to make (namespace mode, install mode, approval) because the CLI labs reproduce them by hand.

**Prerequisites:**
- Cluster-admin.
- Web console access (`oc whoami --show-console` prints the URL).
- A cluster with the default `redhat-operators` catalog source enabled (Developer Sandbox usually restricts OperatorHub — use CRC/SNO/real cluster).

---

#### Step 1 — Console → OperatorHub → search "Web Terminal"

<details>
<summary>💡 Solution</summary>

1. Get the console URL:
   ```bash
   oc whoami --show-console
   # https://console-openshift-console.apps.<cluster-domain>
   ```
2. Log in as a cluster-admin.
3. Left nav → **Operators → OperatorHub**.
4. In the "Filter by keyword" box, type `Web Terminal`.
5. Click the **Web Terminal** tile (publisher: Red Hat).

**Why Web Terminal:** it's small, installs fast, has no required CR to become useful, and cleans up easily — ideal for a lab. (If Web Terminal isn't in your catalog, any small Red Hat operator works: "DevWorkspace Operator", "Cluster Observability Operator", etc.)

</details>

---

#### Step 2 — Install in `openshift-operators` (AllNamespaces, Automatic approval)

<details>
<summary>💡 Solution</summary>

After clicking the tile, click **Install**. The install form presents these choices:

| Field | Choose | What it means |
|-------|--------|---------------|
| **Update channel** | (leave default, usually `fast` or `stable`) | Which stream of versions to track |
| **Installation mode** | "All namespaces on the cluster (default)" | Operator watches every namespace; lands in `openshift-operators` |
| **Installed Namespace** | `openshift-operators` (auto-selected for AllNamespaces) | Where the operator's own pods live |
| **Update approval** | **Automatic** | OLM applies new InstallPlans without asking |

Click **Install** and wait.

**The two installation modes explained:**

- **AllNamespaces** — operator installs into `openshift-operators`, watches the entire cluster. There's a single pre-existing global OperatorGroup there. Most Red Hat operators support this.
- **OwnNamespace / SingleNamespace** — operator watches only its own (or one selected) namespace. Requires a dedicated namespace + an OperatorGroup scoped to that namespace. Used by operators that explicitly don't support cluster-wide mode.

**Why `openshift-operators` for AllNamespaces:** that namespace ships with a global OperatorGroup (`global-operators`) targeting all namespaces, so you don't have to create one. This is exactly what the CLI lab (8.2) has to reproduce manually for OwnNamespace operators.

</details>

---

#### Step 3 — Wait for the CSV to reach `Succeeded`

<details>
<summary>💡 Solution</summary>

**In the console:** Operators → Installed Operators. The Web Terminal operator's **Status** column goes `Installing` → `Succeeded`.

**From the CLI (faster to verify):**

```bash
oc get csv -n openshift-operators -w
# NAME                          DISPLAY         VERSION   PHASE
# web-terminal.v1.x.x           Web Terminal    1.x.x     Installing
# web-terminal.v1.x.x           Web Terminal    1.x.x     Succeeded
```

**Block until ready in a script:**

```bash
oc wait --for=jsonpath='{.status.phase}'=Succeeded \
  csv -l operators.coreos.com/web-terminal.openshift-operators \
  -n openshift-operators --timeout=5m
```

(The exact CSV name and label vary by operator/version; `oc get csv -n openshift-operators` shows you the real name.)

**The CSV (ClusterServiceVersion) is the key object** — it represents the *installed* operator: its deployment, RBAC, owned CRDs, and version. "Operator is installed and healthy" ⇔ "its CSV PHASE is Succeeded".

</details>

---

#### Step 4 — Inspect the installed objects

<details>
<summary>💡 Solution</summary>

```bash
# The CSV
oc get csv -n openshift-operators
# NAME                  DISPLAY        VERSION   REPLACES              PHASE
# web-terminal.v1.x.x   Web Terminal   1.x.x     web-terminal.v1.w.w   Succeeded

# The operator's running pods
oc get pods -n openshift-operators
# NAME                                READY   STATUS    RESTARTS   AGE
# web-terminal-controller-xxxxx       1/1     Running   0          2m

# The Subscription (created automatically by the console)
oc get subscription -n openshift-operators
# NAME           PACKAGE        SOURCE             CHANNEL
# web-terminal   web-terminal   redhat-operators   fast

# The InstallPlan (the approved unit of work that installed the CSV)
oc get installplan -n openshift-operators

# The CRDs this operator owns
oc get csv web-terminal.v1.x.x -n openshift-operators \
  -o jsonpath='{range .spec.customresourcedefinitions.owned[*]}{.kind}{"\t"}{.name}{"\n"}{end}'
```

**The five OLM objects you just touched (memorize the chain):**

```
CatalogSource  →  (package available)
Subscription   →  "I want package X on channel Y"
InstallPlan    →  the concrete set of resources to create (CSV + CRDs + RBAC)
CSV            →  the installed operator (deployment, version, owned CRDs)
OperatorGroup  →  defines which namespaces the operator may watch
```

</details>

---

### Lab 8.2 — Install via CLI (20 min)

This is the exam-critical path: install an operator with nothing but YAML. You'll inspect the package, write a Subscription (plus OperatorGroup if needed), apply, and verify.

**Prerequisites:**
- Cluster-admin.
- `redhat-operators` (or `community-operators`) catalog source available.

---

#### Step 1 — Inspect the packagemanifest to find channel and source

<details>
<summary>💡 Solution</summary>

```bash
# List all available packages (there are hundreds)
oc get packagemanifests -n openshift-marketplace | head

# Find the one you want
oc get packagemanifests -n openshift-marketplace | grep -i devworkspace
# devworkspace-operator   Community Operators   2d

# Inspect it for channels and the default channel
oc get packagemanifest devworkspace-operator -n openshift-marketplace \
  -o jsonpath='{.status.defaultChannel}{"\n"}{range .status.channels[*]}{.name}{" -> "}{.currentCSV}{"\n"}{end}'
# fast
# fast -> devworkspace-operator.v0.x.x

# Which catalog source does it come from?
oc get packagemanifest devworkspace-operator -n openshift-marketplace \
  -o jsonpath='{.status.catalogSource}{"\t"}{.status.catalogSourceNamespace}{"\n"}'
# community-operators   openshift-marketplace
```

**The four facts you need before writing a Subscription:**

| Subscription field | Where it comes from |
|--------------------|---------------------|
| `name` (the package) | `.metadata.name` of the packagemanifest |
| `channel` | `.status.defaultChannel` (or pick a specific one from `.status.channels`) |
| `source` | `.status.catalogSource` (e.g. `redhat-operators`, `community-operators`) |
| `sourceNamespace` | `.status.catalogSourceNamespace` (almost always `openshift-marketplace`) |

**Human-readable full inspection:**

```bash
oc describe packagemanifest devworkspace-operator -n openshift-marketplace | less
```

**Gotcha:** the *package name* (used in Subscription `.spec.name`) is the packagemanifest's `metadata.name`, NOT the CSV name. The CSV name (`devworkspace-operator.v0.x.x`) goes into `.spec.startingCSV` only if you want to pin a specific starting version.

</details>

---

#### Step 2 — Create a Subscription YAML

For a cluster-wide (AllNamespaces) operator you can drop it into the existing `openshift-operators` namespace and reuse its global OperatorGroup. For an OwnNamespace operator you must create a namespace + OperatorGroup first.

<details>
<summary>💡 Solution</summary>

**Case A — AllNamespaces operator into `openshift-operators` (simplest):**

```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: devworkspace-operator
  namespace: openshift-operators
spec:
  channel: fast
  name: devworkspace-operator
  source: community-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
```

No OperatorGroup needed — `openshift-operators` already has the global one.

**Case B — operator that needs its own namespace + OperatorGroup:**

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: my-operator-ns
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: my-operator-og
  namespace: my-operator-ns
spec:
  targetNamespaces:
  - my-operator-ns          # OwnNamespace mode: operator watches only this ns
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: my-operator
  namespace: my-operator-ns
spec:
  channel: stable
  name: my-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
```

**OperatorGroup `spec.targetNamespaces` decides the mode:**

| `targetNamespaces` value | Mode |
|--------------------------|------|
| omitted / empty (`spec: {}`) | AllNamespaces — watch the whole cluster |
| `[ <the-og-namespace> ]` | OwnNamespace — watch only its own namespace |
| `[ ns-a, ns-b ]` | MultiNamespace — watch a specific list |

**Gotcha — only ONE OperatorGroup per namespace.** Two OperatorGroups in the same namespace put every operator there into an error state. `openshift-operators` already has one, so never add another there.

</details>

---

#### Step 3 — Apply and verify the CSV reaches `Succeeded`

<details>
<summary>💡 Solution</summary>

```bash
oc apply -f subscription.yaml
# subscription.operators.coreos.com/devworkspace-operator created

# Watch the whole chain unfold:
oc get subscription devworkspace-operator -n openshift-operators -o jsonpath='{.status.installedCSV}{"\n"}'
# devworkspace-operator.v0.x.x

oc get csv -n openshift-operators -w
# devworkspace-operator.v0.x.x   ...   Installing
# devworkspace-operator.v0.x.x   ...   Succeeded

# Or block until ready:
CSV=$(oc get sub devworkspace-operator -n openshift-operators -o jsonpath='{.status.installedCSV}')
oc wait --for=jsonpath='{.status.phase}'=Succeeded csv/$CSV -n openshift-operators --timeout=5m
```

**If the CSV never appears or stays `Pending`:**

```bash
# Look at the subscription's conditions
oc describe sub devworkspace-operator -n openshift-operators | tail -20

# Look at the install plan
oc get installplan -n openshift-operators
oc describe installplan <name> -n openshift-operators | tail -30
```

Common causes: wrong `source`/`sourceNamespace`, a typo'd package `name`, or (for Case B) a missing/duplicate OperatorGroup.

</details>

---

#### Step 4 — List the CRDs that were installed

<details>
<summary>💡 Solution</summary>

```bash
oc get crd | grep -i devworkspace
# devworkspaceoperatorconfigs.controller.devfile.io
# devworkspaceroutings.controller.devfile.io
# devworkspaces.workspace.devfile.io
# devworkspacetemplates.workspace.devfile.io
```

**More precise — ask the CSV what it owns:**

```bash
CSV=$(oc get sub devworkspace-operator -n openshift-operators -o jsonpath='{.status.installedCSV}')
oc get csv $CSV -n openshift-operators \
  -o jsonpath='{range .spec.customresourcedefinitions.owned[*]}{.kind}{"\t"}{.name}{"\t"}{.version}{"\n"}{end}'
```

**See what API resources the operator added:**

```bash
oc api-resources --api-group=workspace.devfile.io
oc api-resources | grep -i devworkspace
```

**Gotcha for cleanup later:** CRDs are **cluster-scoped** and are NOT deleted when you remove the Subscription or CSV. Lab 8.3 covers purging them.

</details>

---

### Lab 8.3 — Full uninstall + cleanup (15 min)

Uninstalling an operator is a multi-step purge because OLM deliberately leaves your data (CRs and CRDs) behind by default. The exam may ask for a *complete* removal.

**Prerequisites:**
- An operator installed from Lab 8.1 or 8.2.

---

#### Step 1 — Pick an operator and record its details

<details>
<summary>💡 Solution</summary>

```bash
NS=openshift-operators
SUB=devworkspace-operator      # the Subscription name

# Capture the installed CSV name BEFORE you delete the Subscription
CSV=$(oc get sub $SUB -n $NS -o jsonpath='{.status.installedCSV}')
echo "CSV is: $CSV"
# devworkspace-operator.v0.x.x
```

**Why capture the CSV name first:** once you delete the Subscription, the easy link from Sub → CSV is gone, and you'd have to hunt for the CSV by hand. Grab it up front.

</details>

---

#### Step 2 — Delete the Subscription

<details>
<summary>💡 Solution</summary>

```bash
oc delete subscription $SUB -n $NS
# subscription.operators.coreos.com "devworkspace-operator" deleted
```

**Important:** deleting *only* the Subscription does NOT remove the operator. The CSV (and its running pods) stays behind. Verify:

```bash
oc get csv $CSV -n $NS
# Still present — PHASE Succeeded

oc get pods -n $NS
# operator pod STILL running
```

This surprises people. The Subscription is just the "keep this updated" intent; the CSV is the actual install.

</details>

---

#### Step 3 — Delete the CSV

<details>
<summary>💡 Solution</summary>

```bash
oc delete csv $CSV -n $NS
# clusterserviceversion.operators.coreos.com "devworkspace-operator.v0.x.x" deleted
```

Now the operator's Deployment, ServiceAccounts, and RBAC (everything the CSV owned) are removed:

```bash
oc get pods -n $NS
# operator pod gone

oc get deployment -n $NS | grep -i devworkspace
# (no output)
```

**One-liner combining steps 2–3:**

```bash
CSV=$(oc get sub $SUB -n $NS -o jsonpath='{.status.installedCSV}')
oc delete sub $SUB -n $NS
oc delete csv $CSV -n $NS
```

</details>

---

#### Step 4 — Delete any CRs you created against the operator

<details>
<summary>💡 Solution</summary>

If you created custom resources (e.g. a `DevWorkspace`, an `ArgoCD`, a `Pipeline`), delete them. **Do this BEFORE deleting the CRDs** — once the CRD is gone, the CRs become un-deletable orphans (their finalizers can't run because the controller is gone).

```bash
# Find CRs of each owned type, in all namespaces
oc get devworkspaces.workspace.devfile.io -A
oc delete devworkspaces.workspace.devfile.io --all -A

# General pattern for any operator:
for crd in $(oc get crd -o name | grep devfile.io); do
  kind=$(oc get $crd -o jsonpath='{.spec.names.plural}.{.spec.group}')
  echo "Deleting all $kind ..."
  oc delete $kind --all -A 2>/dev/null
done
```

**Gotcha — stuck CRs:** if you already deleted the operator (Step 3) and a CR has a finalizer, it will hang in `Terminating`. Remove the finalizer by hand:

```bash
oc patch devworkspace <name> -n <ns> --type=merge -p '{"metadata":{"finalizers":[]}}'
```

</details>

---

#### Step 5 — Delete the related CRDs (full purge)

<details>
<summary>💡 Solution</summary>

```bash
# List them first
oc get crd | grep -E 'devfile.io|devworkspace'

# Delete them
oc get crd -o name | grep -E 'devfile.io|devworkspace' | xargs oc delete
# customresourcedefinition.apiextensions.k8s.io "devworkspaces.workspace.devfile.io" deleted
# ...
```

**Caution:** CRDs are cluster-scoped and deleting one cascades to **all** CRs of that type in every namespace. Make sure no other team relies on them.

**If you used Case B (dedicated namespace + OperatorGroup) in Lab 8.2, also remove those:**

```bash
oc delete operatorgroup my-operator-og -n my-operator-ns
oc delete namespace my-operator-ns
```

</details>

---

#### Step 6 — Confirm the operator pod is gone

<details>
<summary>💡 Solution</summary>

```bash
oc get pods -n openshift-operators | grep -i devworkspace
# (no output — success)

oc get csv -n openshift-operators | grep -i devworkspace
# (no output)

oc get crd | grep -i devworkspace
# (no output — full purge confirmed)

oc api-resources | grep -i devworkspace
# (no output)
```

**The complete uninstall order, memorized:**

```
1. CRs        (delete instances first, while the controller still runs)
2. Subscription
3. CSV
4. CRDs       (cluster-scoped; cascades to any remaining CRs)
5. OperatorGroup + Namespace  (only if you made a dedicated one)
```

The reason CRs come first: their finalizers need the controller alive to clean up. Everything else (Sub, CSV, CRD) is about removing the operator machinery, innermost-dependency-last.

</details>

---

### Lab 8.4 — Manual approval drill (15 min)

`installPlanApproval: Manual` is a common exam requirement ("install operator X but require an administrator to approve updates"). This drill shows the gated flow end-to-end.

**Prerequisites:**
- Cluster-admin.
- A catalog source available. Use any small operator; the example uses `devworkspace-operator`, but swap freely.

---

#### Step 1 — Create a Subscription with `installPlanApproval: Manual`

<details>
<summary>💡 Solution</summary>

```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: devworkspace-operator
  namespace: openshift-operators
spec:
  channel: fast
  name: devworkspace-operator
  source: community-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Manual          # ← the gate
```

```bash
oc apply -f sub-manual.yaml
# subscription.operators.coreos.com/devworkspace-operator created
```

The only difference from an automatic install is that one field. Everything else (package, channel, source) is identical.

</details>

---

#### Step 2 — Observe that the InstallPlan is created but the CSV stays unstarted

<details>
<summary>💡 Solution</summary>

```bash
# The Subscription reports it's waiting for approval
oc get sub devworkspace-operator -n openshift-operators \
  -o jsonpath='{.status.state}{"\n"}'
# UpgradePending

# An InstallPlan exists, but APPROVED is false
oc get installplan -n openshift-operators
# NAME            CSV                              APPROVAL   APPROVED
# install-abcde   devworkspace-operator.v0.x.x     Manual     false

# No CSV yet (or it's stuck not-installed)
oc get csv -n openshift-operators | grep devworkspace
# (nothing, or no Succeeded phase)

# The Subscription's condition spells it out:
oc describe sub devworkspace-operator -n openshift-operators | grep -A3 "Install Plan"
```

**What's happening:** OLM resolved the dependencies and built an InstallPlan — the concrete list of objects to create — but because approval is Manual, it parks the plan with `spec.approved: false` and waits for a human. No CSV gets installed, no operator pods start.

</details>

---

#### Step 3 — Approve the InstallPlan and watch the CSV reach `Succeeded`

<details>
<summary>💡 Solution</summary>

**Method A — patch the InstallPlan directly:**

```bash
IP=$(oc get installplan -n openshift-operators \
  -o jsonpath='{.items[?(@.spec.approved==false)].metadata.name}')
echo "InstallPlan: $IP"

oc patch installplan $IP -n openshift-operators \
  --type=merge -p '{"spec":{"approved":true}}'
# installplan.operators.coreos.com/install-abcde patched
```

**Method B — console:** Operators → Installed Operators → the operator shows "Upgrade available / Approval required" → click **Review InstallPlan** → **Approve**.

**Watch it proceed:**

```bash
oc get installplan $IP -n openshift-operators \
  -o jsonpath='{.spec.approved}{"\t"}{.status.phase}{"\n"}'
# true   Complete

oc get csv -n openshift-operators -w
# devworkspace-operator.v0.x.x   ...   Installing
# devworkspace-operator.v0.x.x   ...   Succeeded

oc get pods -n openshift-operators | grep devworkspace
# devworkspace-controller-...   1/1   Running
```

**Why Manual approval matters in production (and on the exam):** with Manual, every *future* update also parks an InstallPlan awaiting approval. This lets admins control exactly when an operator upgrades — critical for operators tied to cluster version compatibility, or where an unplanned upgrade could break running workloads. The exam phrasing is usually "configure the operator so that updates are not applied automatically."

**Cleanup (reuse Lab 8.3):**

```bash
CSV=$(oc get sub devworkspace-operator -n openshift-operators -o jsonpath='{.status.installedCSV}')
oc delete sub devworkspace-operator -n openshift-operators
oc delete csv $CSV -n openshift-operators
oc get crd -o name | grep devfile.io | xargs oc delete 2>/dev/null
```

</details>

---

---

## ⚡ Drills (timed, no docs)

| Drill | Target time |
|-------|-------------|
| List all installed operators across the cluster | 30 s |
| Find the channels available for a given operator | 60 s |
| Install an operator via a single `oc apply` of a 10-line Subscription | 90 s |
| Uninstall an operator including its CSV | 60 s |
| Approve a pending InstallPlan | 30 s |
| Disable the `community-operators` CatalogSource | 60 s |

---

## ❗ Common pitfalls

1. **OperatorGroup mismatch:** installing an `OwnNamespace`-only operator in `openshift-operators` (which is AllNamespaces) will leave the CSV `Failed`. Read the operator's supported install modes.
2. **Subscription channel typos** silently leave the CSV in `Pending` — verify `oc describe sub` for warnings.
3. **Deleting the Subscription doesn't delete the CSV** — you have to do both for a real uninstall.
4. **CRDs linger** — explicit `oc delete crd` is needed for a full purge.
5. **Manual approval keeps the operator stuck** until you patch the InstallPlan. The exam may test exactly this.

## 🔗 Docs to bookmark

- OLM concepts: https://docs.openshift.com/container-platform/4.18/operators/understanding/olm/olm-understanding-operatorhub.html
- Install via CLI: https://docs.openshift.com/container-platform/4.18/operators/admin/olm-adding-operators-to-cluster.html#olm-installing-operator-from-operatorhub-using-cli
- Uninstall: https://docs.openshift.com/container-platform/4.18/operators/admin/olm-deleting-operators-from-cluster.html
- Channels & updates: https://docs.openshift.com/container-platform/4.18/operators/admin/olm-upgrading-operators.html
