# Objective 1 - Manage OpenShift Container Platform

> **Exam study points (verbatim from Red Hat EX280 v4.18–4.22):**
> - Use the web console to manage and configure an OpenShift cluster
> - Use the command-line interface to manage and configure an OpenShift cluster
> - Create and delete projects
> - Locate and examine container images
> - Identify images using tags and digests
> - Query, format, and filter attributes of Kubernetes resources
> - Import, export, and configure Kubernetes resources
> - Examine resources and cluster status
> - Monitor cluster events and alerts
> - View logs
> - Assess the health of an OpenShift cluster
> - Troubleshoot common container, pod, and cluster events and alerts
> - Use product documentation
> - Be prepared to perform all tasks of a Red Hat Certified Technologist in OpenShift

Plus, in OCP 4.18–4.22: **be comfortable with cluster updates** (channel selection, EUS-to-EUS upgrades, and MachineConfigPool pausing).

---

## §1 - `oc` and the web console

Both are first-class tools. You'll be faster with `oc` on the exam, but the web console is unbeatable for browsing OperatorHub, events, and YAML schemas.

### Logging in

```bash
# Username/password (HTPasswd, kube:admin, etc.)
oc login -u kubeadmin -p "$PASSWORD" https://api.crc.testing:6443

# Token (web console → top-right user menu → "Copy login command")
oc login --token=sha256~xxxxxxx --server=https://api.example.com:6443

# Where am I, who am I, what are my permissions
oc whoami
oc whoami --show-server
oc whoami --show-console      # URL of the web console
oc whoami --show-token

# Switch users on the same cluster (separate kubeconfig contexts)
oc login -u alice -p alicepw
oc config get-contexts
oc config use-context default/api-crc-testing:6443/alice
```

### Console URL & credentials

```bash
# CRC (OpenShift Local)
crc console
crc console --credentials

# Any cluster: parse from routes
oc get route -n openshift-console console -o jsonpath='{.spec.host}{"\n"}'
```

---

## §2 - Projects (namespaces with extra annotations)

A **Project** is a Kubernetes `Namespace` plus OpenShift annotations (display name, description, requester, and SCC UID/MCS ranges). Always use `oc new-project` / `oc delete project` so the OpenShift project request pipeline and annotations are triggered properly.

```bash
# Create
oc new-project myapp --display-name="My App" --description="EX280 practice"

# Switch
oc project myapp
oc project                       # show current

# List
oc projects                      # human-friendly
oc get projects                  # raw

# Delete (asynchronous; namespace stays "Terminating" for a few seconds)
oc delete project myapp

# Wait until fully gone
oc wait --for=delete project/myapp --timeout=60s
```

> ⚠️ **Exam Rule:** Read the prompt for the **exact** project name—it is case-sensitive and hyphens matter. Run `oc project <name>` immediately so all subsequent commands land in the right namespace.

---

## §3 - Container images: tags & digests

OpenShift pulls images by **tag** (`:1.2.0`, `:latest`) or **digest** (`@sha256:abc…`). Digests are immutable; tags are mutable pointers.

```bash
# Inspect a remote image without pulling its layers
oc image info quay.io/openshifttest/hello-openshift:1.2.0

# Extract the immutable digest from a tag
oc image info quay.io/openshifttest/hello-openshift:1.2.0 --output=json | jq -r .digest

# Pull and re-tag into the internal registry (ImageStream)
oc import-image hello:1.2.0 \
  --from=quay.io/openshifttest/hello-openshift:1.2.0 \
  --confirm -n myapp

oc get is hello -n myapp
oc get istag hello:1.2.0 -n myapp
```

### ImageStreams: OpenShift's image abstraction

```yaml
apiVersion: image.openshift.io/v1
kind: ImageStream
metadata:
  name: hello
spec:
  lookupPolicy:
    local: true                # let pods/deployments in this namespace reference this IS by short name
  tags:
    - name: "1.2.0"
      from:
        kind: DockerImage
        name: quay.io/openshifttest/hello-openshift:1.2.0
      importPolicy:
        scheduled: true        # periodically check upstream registry for a new digest
```

Apply with `oc apply -f imagestream.yaml`.

---

## §4 - Querying resources: format & filter

This is exam gold. Master these filters so you never rely on brittle `grep`/`awk` text parsing.

```bash
# Default + wide
oc get pods
oc get pods -o wide

# YAML / JSON
oc get pod mypod -o yaml
oc get pod mypod -o json | jq '.status.phase'

# Custom columns
oc get pods -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName

# JSONPath
oc get pods -o jsonpath='{.items[*].metadata.name}{"\n"}'
oc get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.podIP}{"\n"}{end}'

# Label selectors
oc get pods -l app=hello
oc get pods -l 'app in (hello,nodejs)'
oc get pods -l 'environment!=prod'

# Common workload resources in a namespace
oc get all -n myapp

# All resource types on the cluster (including CRDs and shortnames)
oc api-resources
oc api-resources --namespaced=true
oc api-resources --api-group=apps

# Watch a resource live
oc get pods -w
```

> ⚠️ **Exam Trap (`oc get all`):** Despite its name, `oc get all` **only** returns Pods, Services, Deployments, ReplicaSets, StatefulSets, Jobs, CronJobs, Routes, and ImageStreams. It **hides** `ConfigMap`, `Secret`, `PersistentVolumeClaim`, `NetworkPolicy`, `ResourceQuota`, `LimitRange`, `ServiceAccount`, and `RoleBinding`. Always inspect those explicitly:
> ```bash
> oc get cm,secret,pvc,netpol,quota,limitrange,sa,rolebinding -n myapp
> ```

### Field selectors & sorting

```bash
# Field selectors (server-side filtering on status/spec fields)
oc get pods -A --field-selector=status.phase=Running
oc get events --field-selector=involvedObject.kind=Pod,type=Warning

# Sorting (takes a raw JSONPath path without curly braces)
oc get pods --sort-by=.status.startTime
oc get events --sort-by=.lastTimestamp
```

---

## §5 - Importing, exporting, editing resources

```bash
# Export an existing resource as YAML (omitting noisy managedFields)
oc get deployment hello -o yaml --show-managed-fields=false > hello.yaml

# Apply (declarative — creates or updates)
oc apply -f hello.yaml

# Create (imperative — errors if it already exists)
oc create -f hello.yaml

# Replace (full overwrite of existing object)
oc replace -f hello.yaml

# Edit live (opens $EDITOR; applied on save)
oc edit deployment hello

# Patch (strategic merge or JSON RFC 6902 patch)
oc patch deployment hello -p '{"spec":{"replicas":3}}'
oc patch deployment hello --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/image","value":"nginx:1.27"}]'

# Generate YAML without applying (the exam-day cheat code)
oc create deployment hello --image=nginx --replicas=3 --dry-run=client -o yaml > hello.yaml
oc create configmap mycfg --from-literal=key=value --dry-run=client -o yaml
oc create secret generic mysec --from-literal=password=hunter2 --dry-run=client -o yaml
```

---

## §6 - Cluster & resource status

```bash
# Are all platform operators healthy?
oc get clusteroperators
oc get co     # short form
oc describe co kube-apiserver

# Cluster version & upgrade channel
oc get clusterversion
oc adm upgrade

# Nodes & their roles
oc get nodes
oc get nodes --show-labels
oc get nodes -L node-role.kubernetes.io/worker
oc describe node worker-0 | less

# Real-time CPU and memory utilization
oc adm top nodes
oc adm top pods -A
```

---

## §7 - Events, logs, troubleshooting

```bash
# Events for a namespace (most recent last)
oc get events --sort-by=.lastTimestamp
oc get events -A --field-selector=type=Warning

# A specific pod's logs
oc logs mypod
oc logs mypod -c container2          # multi-container pod
oc logs deployment/hello             # latest replica of a deployment
oc logs mypod --previous             # crashed container's last logs
oc logs -f mypod                     # follow live

# Describe = spec + status + recent events of the object
oc describe pod mypod

# Exec into a running container
oc rsh mypod                         # opens shell in default container
oc rsh -c sidecar mypod
oc exec mypod -- ls /etc

# Open a debug pod (starts a troubleshooting copy when a container won't stay up)
oc debug pod/mypod                   # same image, overrides entrypoint to shell
oc debug node/worker-0               # node-level debug pod with `chroot /host`
oc debug deployment/hello --as-root

# Node-level systemd journal logs (kubelet, crio)
oc adm node-logs worker-0
oc adm node-logs worker-0 -u kubelet
oc adm node-logs worker-0 -u crio --tail=50

# Cluster-wide must-gather (for support tickets / postmortems)
oc adm must-gather --dest-dir=./must-gather-$(date +%s)
```

### Classic troubleshooting flow

```text
Pod stuck Pending          → oc describe pod → look at Events → fix scheduling (resources, taints, nodeSelector, PVC)
Pod CrashLoopBackOff       → oc logs --previous → fix entrypoint command, permissions (SCC), or missing env/secret
ImagePullBackOff           → oc describe pod → wrong image/tag or missing pull secret?
Service has no endpoints   → oc get endpoints svc/x → label mismatch between Service.spec.selector and Pod.metadata.labels
Route 503 / 404            → oc get route → wrong service, targetPort mismatch, or failing readinessProbe
RBAC / API denial          → oc auth can-i <verb> <resource> -n <ns> --as=<user>
```

---

## §8 - Monitoring & alerts

OCP 4.18–4.22 ships an integrated monitoring stack (Prometheus + Alertmanager + Thanos Querier).

```bash
# Open the console → Observe → Alerting → Alerts
oc whoami --show-console

# CLI: check monitoring stack health
oc -n openshift-monitoring get pods
oc -n openshift-monitoring get prometheuses,alertmanagers

# Query the alerting API route
oc -n openshift-monitoring get route thanos-querier
```

User-workload monitoring (for your own custom applications and AI metrics) is opt-in via ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    enableUserWorkload: true
```

---

## §9 - OpenShift cluster updates (OCP 4.18 – 4.22)

```bash
# Available updates on the current channel
oc adm upgrade

# Switch channel (stable-4.22, fast-4.22, candidate-4.22, eus-4.22)
oc adm upgrade channel stable-4.22

# Start an update
oc adm upgrade --to-latest=true
oc adm upgrade --to=4.22.2

# Watch progress
oc get clusterversion -w
oc get clusteroperators

# Pause / resume a MachineConfigPool to stagger worker node reboots
oc patch machineconfigpool worker --type=merge -p '{"spec":{"paused":true}}'
oc patch machineconfigpool worker --type=merge -p '{"spec":{"paused":false}}'
```

> **EUS-to-EUS Upgrades:** Extended Update Support releases (even-numbered minor versions: `4.14` → `4.16` → `4.18` → `4.20` → `4.22`) allow you to pause worker `MachineConfigPools`, upgrade the control plane across two minor versions, and unpause the workers so worker nodes only reboot **once**.

---

## 🧪 Labs

### Lab 1.1 - Project lifecycle (10 min)

This lab walks through the four moments in a project's life: create, inspect, populate, delete. Each step has a collapsible Solution.

**Prerequisites:** Logged in as `cluster-admin` (or any user with `self-provisioner`).

1. Create a project `lab11`.
2. Show its annotations: `oc get project lab11 -o yaml` — note `openshift.io/requester`.
3. Switch to it and create a pod from `quay.io/openshifttest/hello-openshift:1.2.0`.
4. Delete the project; wait for `Terminating` to finish.

<details>
<summary>💡 Solution Step 1</summary>

```bash
oc new-project lab11
# Now using project "lab11" on server "https://api.<cluster>:6443".
```

`oc new-project` is the user-facing command—it creates the project **and** switches your current kubeconfig context to it.

Alternative (`cluster-admin` only):

```bash
oc create namespace lab11
oc project lab11
```

The two are **not** equivalent in OpenShift:
- `oc new-project` goes through the `ProjectRequest` API, applies the cluster's custom project template (if configured), and sets `openshift.io/requester` to your username.
- `oc create namespace` bypasses the template and does not set the requester annotation.

</details>

<details>
<summary>💡 Solution Step 2</summary>

```bash
oc get project lab11 -o yaml
```

Look in the `metadata.annotations` block. Key entries to recognize:

```yaml
metadata:
  annotations:
    openshift.io/description: ""
    openshift.io/display-name: ""
    openshift.io/requester: kubeadmin        # ← who requested this project
    openshift.io/sa.scc.mcs: s0:c26,c10      # SELinux MCS category labels
    openshift.io/sa.scc.supplemental-groups: 1000680000/10000
    openshift.io/sa.scc.uid-range: 1000680000/10000
```

Direct extract via `jsonpath` (note the `\.` to escape the dot inside the annotation key):

```bash
oc get project lab11 -o jsonpath='{.metadata.annotations.openshift\.io/requester}{"\n"}'
# kubeadmin
```

**Why this matters:** `openshift.io/requester` drives the `annotationSelector` mode of `ClusterResourceQuota`—allowing platform engineers to enforce per-user multi-project quotas automatically.

</details>

<details>
<summary>💡 Solution Step 3</summary>

You are already inside `lab11` after Step 1. If not:

```bash
oc project lab11
```

Create the pod:

```bash
oc run hello --image=quay.io/openshifttest/hello-openshift:1.2.0
# pod/hello created
```

Verify:

```bash
oc get pod hello -w
# hello   0/1   ContainerCreating   0   3s
# hello   1/1   Running             0   12s

oc logs hello
# serving on 8080
# serving on 8888
```

**Gotcha:** `oc run` creates a bare `Pod`, not a `Deployment`. On the exam, always prefer `oc create deployment` unless the task explicitly asks for a single Pod.

</details>

<details>
<summary>💡 Solution Step 4</summary>

```bash
oc delete project lab11 --wait=true
# project.project.openshift.io "lab11" deleted
```

If a project ever hangs in `Terminating` indefinitely, inspect remaining resources or stuck finalizers:

```bash
oc get project lab11 -o json | jq '.spec.finalizers, .metadata.finalizers'
```

</details>

---

### Lab 1.2 - Querying & filtering (15 min)

All four steps target the `openshift-monitoring` namespace. This lab builds muscle memory for `jsonpath` and `custom-columns`.

In `openshift-monitoring`:

1. List all pods sorted by start time.
2. Show only their names and node names (`custom-columns`).
3. List only pods with label `app.kubernetes.io/component=prometheus`.
4. Get the image of the first container of each prometheus pod (`jsonpath`).

<details>
<summary>💡 Solution Step 1</summary>

```bash
oc get pods -n openshift-monitoring --sort-by=.status.startTime
```

Other useful sort keys:

```bash
oc get pods -n openshift-monitoring --sort-by=.metadata.creationTimestamp
oc get pods -A --sort-by='.status.containerStatuses[0].restartCount'
```

**Gotcha:** `--sort-by` takes a bare path (`--sort-by=.status.startTime`), **not** curly braces.

</details>

<details>
<summary>💡 Solution Step 2</summary>

```bash
oc get pods -n openshift-monitoring \
  -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName
```

To omit the header line (great for scripts):

```bash
oc get pods -n openshift-monitoring \
  -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName --no-headers
```

</details>

<details>
<summary>💡 Solution Step 3</summary>

```bash
oc get pods -n openshift-monitoring -l app.kubernetes.io/component=prometheus
```

Other label and field selector patterns:

```bash
# Set-based selector
oc get pods -n openshift-monitoring -l 'app.kubernetes.io/component in (prometheus,alertmanager)'

# Field selector (for status/spec attributes)
oc get pods -A --field-selector=status.phase=Running
```

</details>

<details>
<summary>💡 Solution Step 4</summary>

```bash
oc get pods -n openshift-monitoring \
  -l app.kubernetes.io/component=prometheus \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'
```

To iterate over **all** containers inside every matching pod:

```bash
oc get pods -n openshift-monitoring \
  -l app.kubernetes.io/component=prometheus \
  -o jsonpath='{range .items[*]}{.metadata.name}{":"}{range .spec.containers[*]}{" "}{.image}{end}{"\n"}{end}'
```

</details>

---

### Lab 1.3 - Imperative → declarative (15 min)

The "generate YAML, edit, and apply" workflow is the single fastest exam habit.

**Prerequisites:** `oc new-project lab13`

1. Produce a `web.yaml` file from an imperative command for a Deployment named `web` using `quay.io/openshifttest/hello-openshift:1.2.0` with `2` replicas, without creating it on the cluster yet.
2. Edit `web.yaml` to add resource requests (`100m` CPU, `128Mi` memory) and limits (`500m` CPU, `256Mi` memory).
3. Apply `web.yaml` to the cluster.
4. Scale `replicas` to `4` using `oc patch`, `oc edit`, or `oc scale`.

<details>
<summary>💡 Solution Step 1</summary>

```bash
oc create deployment web \
  --image=quay.io/openshifttest/hello-openshift:1.2.0 \
  --replicas=2 \
  --dry-run=client -o yaml > web.yaml
```

</details>

<details>
<summary>💡 Solution Step 2</summary>

Update the `containers:` section in `web.yaml`:

```yaml
      containers:
      - image: quay.io/openshifttest/hello-openshift:1.2.0
        name: hello-openshift
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
```

Validate server-side before applying:

```bash
oc apply -f web.yaml --dry-run=server
```

</details>

<details>
<summary>💡 Solution Step 3</summary>

```bash
oc apply -f web.yaml
oc get deployment web
```

</details>

<details>
<summary>💡 Solution Step 4</summary>

```bash
# Method A: oc patch
oc patch deployment web --type=merge -p '{"spec":{"replicas":4}}'

# Method B: oc scale
oc scale deployment/web --replicas=4

# Cleanup
oc delete project lab13
```

</details>

---

### Lab 1.4 - Break & fix (25 min)

**Prerequisites:** `oc new-project lab14`

1. Deploy a broken app: `oc new-app --image=quay.io/openshifttest/hello-openshift:does-not-exist --name=broken-web`.
2. Identify the root cause using `oc describe` and `oc get events`.
3. Fix the deployment by updating the image to `quay.io/openshifttest/hello-openshift:1.2.0`.
4. Break it again by scaling to `2` replicas and requesting `1000` CPU cores. Diagnose the `FailedScheduling` event and revert to `100m` CPU.

<details>
<summary>💡 Solution Step 1</summary>

```bash
oc new-app --image=quay.io/openshifttest/hello-openshift:does-not-exist --name=broken-web
oc get pods
```

</details>

<details>
<summary>💡 Solution Step 2</summary>

```bash
oc describe pod -l app=broken-web
oc get events --sort-by=.lastTimestamp --field-selector=type=Warning
```

</details>

<details>
<summary>💡 Solution Step 3</summary>

```bash
oc set image deployment/broken-web broken-web=quay.io/openshifttest/hello-openshift:1.2.0
oc rollout status deployment/broken-web
```

</details>

<details>
<summary>💡 Solution Step 4</summary>

```bash
# Break scheduling
oc scale deployment/broken-web --replicas=2
oc set resources deployment/broken-web --requests=cpu=1000

# Diagnose Pending pod
oc describe pod -l app=broken-web --field-selector=status.phase=Pending

# Fix CPU request
oc set resources deployment/broken-web --requests=cpu=100m
oc rollout status deployment/broken-web

# Cleanup
oc delete project lab14
```

</details>

---

### Lab 1.5 - Cluster ops sweep (20 min)

1. Check `oc get clusteroperators` — are any `AVAILABLE=False` or `DEGRADED=True`?
2. Inspect one operator with `oc describe co <name>` and read its `Conditions`.
3. Check top resource consumers with `oc adm top nodes` and `oc adm top pods -A`.
4. Find the top 5 noisiest pods by log lines in `openshift-monitoring`.

<details>
<summary>💡 Solution Step 1</summary>

```bash
oc get co
# Filter for any operator not in True / False / False (Available / Progressing / Degraded)
oc get co | grep -Ev 'True\s+False\s+False'
```

</details>

<details>
<summary>💡 Solution Step 2</summary>

```bash
oc get co authentication -o jsonpath='{range .status.conditions[*]}{.type}={.status}{"\t"}{.message}{"\n"}{end}'
```

</details>

<details>
<summary>💡 Solution Step 3</summary>

```bash
oc adm top nodes --sort-by=cpu
oc adm top pods -A --sort-by=memory | head -n 15
```

</details>

<details>
<summary>💡 Solution Step 4</summary>

```bash
for p in $(oc get pods -n openshift-monitoring -o name); do
  printf "%6d  %s\n" "$(oc logs --since=5m -n openshift-monitoring "$p" 2>/dev/null | wc -l)" "$p"
done | sort -rn | head -n 5
```

</details>

---

### Lab 1.6 - Cluster update dry-run (CRC) (15 min)

1. Run `oc adm upgrade` — note the current channel and available target versions.
2. Switch the channel to `candidate-4.18` (or `candidate-4.22`), verify in `ClusterVersion`, and switch back.
3. Pause the `worker` `MachineConfigPool`, inspect its state, and unpause it.

<details>
<summary>💡 Solution Step 1</summary>

```bash
oc adm upgrade
oc get clusterversion -o yaml
```

</details>

<details>
<summary>💡 Solution Step 2</summary>

```bash
# Save current channel first
ORIG_CHAN=$(oc get clusterversion version -o jsonpath='{.spec.channel}')

# Switch channel
oc adm upgrade channel candidate-4.18
oc get clusterversion version -o jsonpath='{.spec.channel}{"\n"}'

# Restore original channel
oc adm upgrade channel "$ORIG_CHAN"
```

</details>

<details>
<summary>💡 Solution Step 3</summary>

```bash
# Pause worker reboot rollouts
oc patch mcp worker --type=merge -p '{"spec":{"paused":true}}'
oc get mcp worker -o jsonpath='{.spec.paused}{"\n"}'

# Unpause worker pool
oc patch mcp worker --type=merge -p '{"spec":{"paused":false}}'
oc get mcp
```

</details>

---

## ⚡ Drills (timed, no docs)

| Drill | Target time |
|-------|-------------|
| Log in to a cluster from a fresh shell using a token | 30 s |
| Create a project named exactly `team-alpha-prod` | 15 s |
| Get all pods cluster-wide in `Pending` state | 30 s |
| Get the image of the first container in all pods in `openshift-monitoring` | 60 s |
| Show the last 5 `Warning` events across all namespaces | 45 s |
| List the `clusteroperators` whose `Available` condition is `False` | 30 s |
| Tail-follow logs of every container in `deployment/hello` | 30 s |
| Open a debug shell on a worker node and `chroot /host` | 60 s |

---

## 🔗 Docs links to bookmark

- CLI Tools (`oc`): <https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/cli_tools/openshift-cli-oc>
- Projects: <https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/building_applications/projects>
- Managing Images: <https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/images/managing-images>
- Updating Clusters: <https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/updating_clusters/index>
- Support & Troubleshooting: <https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/support/troubleshooting>
