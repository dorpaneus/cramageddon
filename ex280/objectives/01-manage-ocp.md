<div align="center">

[⬅️ Prev: Home](../README.md) &nbsp;·&nbsp; [🏠 Home](../README.md) &nbsp;·&nbsp; [Next: Work with resource manifests ➡️](./02-resource-manifests.md)

</div>

# Objective 1 - Manage OpenShift Container Platform

> **Exam study points (verbatim from Red Hat):**
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

Also covered (DO280 course content, **not** an EX280 objective): cluster updates — channel selection, EUS-to-EUS, MCP pausing. See §9 and Lab 1.6.

## §1 - `oc` and the web console

Both are first-class tools. You'll be faster with `oc` on the exam, but the web console is unbeatable for browsing operators, events, and YAML.

### Logging in

```bash
# Username/password (HTPasswd, kube:admin, etc.)
oc login -u kubeadmin -p $PASSWORD https://api.crc.testing:6443

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
# CRC
crc console
crc console --credentials

# Any cluster: parse from routes
oc get route -n openshift-console console -o jsonpath='{.spec.host}'
```

## §2 - Projects (namespaces with extra annotations)

A **Project** is a Kubernetes `Namespace` plus OpenShift annotations (display name, description, requester). Always use `oc new-project` / `oc delete project` so the annotations come along.

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

> ⚠️ On the exam, **read the prompt for the exact project name** - case-sensitive, hyphens matter. Use `oc project <name>` immediately so all subsequent commands land in the right place.

## §3 - Container images: tags & digests

OpenShift pulls images by **tag** (`:1.2.0`, `:latest`) or **digest** (`@sha256:abc…`). Digests are immutable; tags can move.

```bash
# Inspect an image without pulling it
oc image info quay.io/openshifttest/hello-openshift:1.2.0

# Get the digest from a tag
oc image info quay.io/openshifttest/hello-openshift:1.2.0 --output=json | jq -r .digest

# Pull and re-tag into the internal registry (image stream)
oc import-image hello:1.2.0 --from=quay.io/openshifttest/hello-openshift:1.2.0 \
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
    local: true                # let pods reference this IS directly
  tags:
    - name: "1.2.0"
      from:
        kind: DockerImage
        name: quay.io/openshifttest/hello-openshift:1.2.0
      importPolicy:
        scheduled: true        # periodically check for new digest
```

Apply with `oc apply -f imagestream.yaml`.

## §4 - Querying resources: format & filter

This is exam gold. Master these.

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
oc get pods -o jsonpath='{.items[*].metadata.name}'
oc get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.podIP}{"\n"}{end}'

# Label selectors
oc get pods -l app=hello
oc get pods -l 'app in (hello,nodejs)'
oc get pods -l 'environment!=prod'

# All resources in a namespace
oc get all -n myapp

# All resource types ever (incl. CRDs)
oc api-resources
oc api-resources --namespaced=true
oc api-resources --api-group=apps

# Watch a resource live
oc get pods -w
```

### Field selectors

```bash
oc get pods --field-selector=status.phase=Running
oc get events --field-selector=involvedObject.kind=Pod,type=Warning
```

### Sorting

```bash
oc get pods --sort-by=.status.startTime
oc get events --sort-by=.lastTimestamp
```

## §5 - Importing, exporting, editing resources

```bash
# Export an existing resource as YAML (no cluster-side fields)
oc get deployment hello -o yaml > hello.yaml      # has status, resourceVersion etc.
oc get deployment hello -o yaml --show-managed-fields=false > hello.yaml

# Apply (declarative — creates or updates)
oc apply -f hello.yaml

# Create (errors if it already exists)
oc create -f hello.yaml

# Replace (full overwrite)
oc replace -f hello.yaml

# Edit live (opens $EDITOR; the change is applied on save)
oc edit deployment hello

# Patch (great for one-liners)
oc patch deployment hello -p '{"spec":{"replicas":3}}'
oc patch deployment hello --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/image","value":"nginx:1.27"}]'

# Generate YAML without applying (the exam-day cheat code)
oc create deployment hello --image=nginx --replicas=3 --dry-run=client -o yaml > hello.yaml
oc create configmap mycfg --from-literal=key=value --dry-run=client -o yaml
oc create secret generic mysec --from-literal=password=hunter2 --dry-run=client -o yaml
```

## §6 - Cluster & resource status

```bash
# Are all platform operators healthy?
oc get clusteroperators
oc get co     # short form
oc describe co kube-apiserver

# Cluster version & channel
oc get clusterversion
oc adm upgrade

# Nodes & their roles
oc get nodes
oc get nodes --show-labels
oc get nodes -L node-role.kubernetes.io/worker
oc describe node worker-0 | less

# Resources used per node
oc adm top nodes
oc adm top pods -A
```

## §7 - Events, logs, troubleshooting

```bash
# Events for a namespace (most recent last)
oc get events --sort-by=.lastTimestamp
oc get events -A --field-selector=type=Warning

# A specific pod's logs
oc logs mypod
oc logs mypod -c container2          # multi-container
oc logs deployment/hello             # latest replica
oc logs mypod --previous             # crashed pod's last logs
oc logs -f mypod                     # follow

# Describe = events + spec + status of the object
oc describe pod mypod

# Exec into a container
oc rsh mypod                         # default container
oc rsh -c sidecar mypod
oc exec mypod -- ls /etc

# Open a debug pod (no exec into a broken container — start a new one!)
oc debug pod/mypod                   # same image, no entrypoint
oc debug node/worker-0               # node-level debug pod with `chroot /host`
oc debug deployment/hello --as-root

# Node-level logs (kubelet, crio)
oc adm node-logs worker-0
oc adm node-logs worker-0 -u kubelet
oc adm node-logs worker-0 -u crio --tail=50

# Cluster-wide must-gather (for support tickets / postmortems)
oc adm must-gather --dest-dir=./must-gather-$(date +%s)
```

### Classic troubleshooting flow

```
Pod stuck Pending          → oc describe pod → look at Events → fix scheduling (resources, taints, nodeSelector)
Pod CrashLoopBackOff       → oc logs --previous → fix command/image/env
ImagePullBackOff           → oc describe → wrong image/tag/pull-secret? oc get events for auth errors
Service has no endpoints   → oc get endpointslices -l kubernetes.io/service-name=x → Service.selector ≠ Pod labels, or pods not Ready
Route 503 / 404            → oc get route → wrong service / wrong port / TLS termination wrong
RBAC error                 → oc auth can-i <verb> <resource> -n <ns> --as=<user>
```

## §8 - Monitoring & alerts

OCP 4.18 ships an integrated monitoring stack (Prometheus + Alertmanager + Thanos). You don't manage it deeply on EX280, but you should be able to **find** alerts.

```bash
# Open the console → Observe → Alerting → Alerts
oc whoami --show-console

# CLI: prometheus / alertmanager are operands of the cluster-monitoring-operator
oc -n openshift-monitoring get pods
oc -n openshift-monitoring get prometheuses,alertmanagers

# Query the alerting API (read-only) via the thanos route
oc -n openshift-monitoring get route thanos-querier
```

User-workload monitoring (for your own apps) is opt-in:

```yaml
# cluster-monitoring-config in openshift-monitoring
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    enableUserWorkload: true
```

## §9 - OpenShift cluster updates (DO280 course content, not an EX280 objective)

```bash
# Available updates on the current channel
oc adm upgrade

# Switch channel (stable-4.18, fast-4.18, candidate-4.18, eus-4.18)
oc adm upgrade channel stable-4.18

# Start an update
oc adm upgrade --to-latest=true
oc adm upgrade --to=4.18.7

# Watch progress
oc get clusterversion -w
oc get clusteroperators

# Pause / resume a MachineConfigPool to stagger node updates
oc patch machineconfigpool worker --type=merge -p '{"spec":{"paused":true}}'
oc patch machineconfigpool worker --type=merge -p '{"spec":{"paused":false}}'
```

> EUS-to-EUS upgrades (Extended Update Support: 4.14 → 4.16 → 4.18) pause workers across two minor versions, then unpause once you're on the target EUS minor. Practice the pause/unpause pattern in CRC.

## 🧪 Labs

### Lab 1.1 - Project lifecycle (10 min)

This lab walks through the four moments in a project's life: create, inspect, populate, delete. Each step has a collapsible Solution.

**Prerequisites:** logged in as cluster-admin (or any user with `self-provisioner`). `oc` CLI version close to your cluster's.

1. Create a project `lab11`.
2. Show its annotations: `oc get project lab11 -o yaml` - note `openshift.io/requester`.
3. Switch to it and create a pod from `quay.io/openshifttest/hello-openshift:1.2.0`.
4. Delete the project; wait for `Terminating` to finish.

<details>
<summary>💡 Solution Step 1</summary>

```bash
oc new-project lab11
# Now using project "lab11" on server "https://api.<cluster>:6443".
```

`oc new-project` is the user-facing command — it creates the project **and** switches your context to it.

Alternative (cluster-admin only):

```bash
oc create namespace lab11
oc project lab11
```

The two are **not** equivalent in OpenShift:

- `oc new-project` goes through the project request API, applies the project template (if one is configured), and sets `openshift.io/requester` to your username.
- `oc create namespace` bypasses that — no requester annotation, no template processing.

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
    openshift.io/requester: kubeadmin        # ← who asked for this project
    openshift.io/sa.scc.mcs: s0:c26,c10      # SCC MCS labels
    openshift.io/sa.scc.supplemental-groups: 1000680000/10000
    openshift.io/sa.scc.uid-range: 1000680000/10000
```

Direct extract via jsonpath:

```bash
oc get project lab11 -o jsonpath='{.metadata.annotations.openshift\.io/requester}{"\n"}'
# kubeadmin
```

(Note the `\.` to escape the dot inside the annotation key.)

**Why this matters:** `openshift.io/requester` drives the annotation-selector mode of `ClusterResourceQuota` — you can build "per-developer quota" rules that automatically apply to every project a given user creates.

</details>

<details>
<summary>💡 Solution Step 3</summary>

You're already inside `lab11` after Step 1. If not:

```bash
oc project lab11
```

Create the pod (simplest form):

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

**Gotcha — `oc run` creates a bare Pod, not a Deployment.** A bare Pod isn't recreated by a controller if it's deleted or its node fails. On the exam, prefer:

```bash
oc create deployment hello --image=quay.io/openshifttest/hello-openshift:1.2.0
```

unless the task explicitly asks for a Pod.

</details>

<details>
<summary>💡 Solution Step 4</summary>

```bash
oc delete project lab11
# project.project.openshift.io "lab11" deleted

# Watch the status until the project disappears entirely:
oc get project lab11 -w
# NAME    DISPLAY NAME   STATUS
# lab11                  Terminating
# (... typically 5–20 seconds ...)
# Error from server (NotFound): namespaces "lab11" not found
```

Alternative — block until deleted (cleaner in scripts):

```bash
oc delete project lab11 --wait=true
# or, after a plain delete:
oc wait --for=delete namespace/lab11 --timeout=60s
```

**If the project hangs in `Terminating` forever:** there's a stuck finalizer, usually on a custom resource managed by an operator that's no longer running. To diagnose:

```bash
oc get namespace lab11 -o jsonpath='{.status.conditions}{"\n"}'   # names the blocking resources
oc get all,pvc,configmap,secret,role,rolebinding -n lab11
```

Force-removal (use carefully — last resort):

```bash
oc get namespace lab11 -o json \
  | jq '.spec.finalizers = []' \
  | oc replace --raw "/api/v1/namespaces/lab11/finalize" -f -
```

On the exam, projects normally terminate in seconds. If yours doesn't, suspect a misconfigured operator.

</details>

---

### Lab 1.2 - Querying & filtering (15 min)

All four steps target the `openshift-monitoring` namespace, which always has a healthy set of pods on a real cluster. This lab is muscle memory for the exam — you'll use `-o jsonpath` and `custom-columns` constantly.

**Prerequisites:** read access to `openshift-monitoring` (cluster-admin or cluster-reader works).

In `openshift-monitoring`:

1. List all pods sorted by start time.
2. Show only their names and node names (custom columns).
3. List only pods with label `app.kubernetes.io/component=prometheus`.
4. Get the image of the first container of each prometheus pod (jsonpath).

<details>
<summary>💡 Solution Step 1</summary>

```bash
oc get pods -n openshift-monitoring --sort-by=.status.startTime
```

Newest pods are at the bottom. To reverse:

```bash
oc get pods -n openshift-monitoring --sort-by=.status.startTime --no-headers | tac
```

Alternative sort keys you'll want to know:

```bash
oc get pods -n openshift-monitoring --sort-by=.metadata.creationTimestamp
oc get pods -n openshift-monitoring --sort-by=.status.phase
oc get pods -A --sort-by='.status.containerStatuses[0].restartCount'    # restart troublemakers at the bottom
```

**Gotcha — `--sort-by` takes a single JSONPath expression**, not the templated `{...}` form. Don't write `--sort-by='{.status.startTime}'`.

</details>

<details>
<summary>💡 Solution Step 2</summary>

```bash
oc get pods -n openshift-monitoring \
  -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName
```

Output:

```text
NAME                                          NODE
alertmanager-main-0                           worker-0
prometheus-k8s-0                              worker-1
prometheus-k8s-1                              worker-2
...
```

Variants worth knowing:

```bash
# Skip the header (useful in scripts):
oc get pods -n openshift-monitoring \
  -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName --no-headers

# Save the columns spec to a file and reuse:
cat > cols.txt <<EOF
NAME      NODE           STATUS
.metadata.name .spec.nodeName .status.phase
EOF
oc get pods -n openshift-monitoring -o custom-columns-file=cols.txt
```

(The columns file is two lines: headers on the first, matching field paths on the second.)

**Gotcha — array indexing in custom columns:** for `containers[0].image` use brackets, not dots:

```bash
oc get pods -n openshift-monitoring \
  -o custom-columns='NAME:.metadata.name,IMAGE:.spec.containers[0].image'
```

</details>

<details>
<summary>💡 Solution Step 3</summary>

```bash
oc get pods -n openshift-monitoring -l app.kubernetes.io/component=prometheus
```

Output (typical):

```text
NAME                READY   STATUS    RESTARTS   AGE
prometheus-k8s-0    6/6     Running   0          2d
prometheus-k8s-1    6/6     Running   0          2d
```

Other selector forms to memorize:

```bash
# Two labels (AND)
oc get pods -n openshift-monitoring \
  -l app.kubernetes.io/component=prometheus,app.kubernetes.io/instance=k8s

# Label exists (any value)
oc get pods -n openshift-monitoring -l app.kubernetes.io/component

# Label does NOT equal
oc get pods -n openshift-monitoring -l 'app.kubernetes.io/component!=alertmanager'

# Set-based: in / notin
oc get pods -n openshift-monitoring \
  -l 'app.kubernetes.io/component in (prometheus,alertmanager)'

# Label NOT present
oc get pods -n openshift-monitoring -l '!app.kubernetes.io/component'
```

Field selectors are a different mechanism (not labels) — for status, phase, node name:

```bash
oc get pods -A --field-selector=status.phase=Running
oc get pods -A --field-selector=spec.nodeName=worker-0
```

</details>

<details>
<summary>💡 Solution Step 4</summary>

```bash
oc get pods -n openshift-monitoring \
  -l app.kubernetes.io/component=prometheus \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'
```

Output:

```text
prometheus-k8s-0   quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:...
prometheus-k8s-1   quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:...
```

Anatomy of the jsonpath expression:

| Fragment | Meaning |
|----------|---------|
| `{range .items[*]}` … `{end}` | Iterate over each item in the list |
| `{.metadata.name}` | Print the pod's name |
| `{"\t"}` | Literal tab |
| `{.spec.containers[0].image}` | Image of the first container |
| `{"\n"}` | Literal newline |

Common variants:

```bash
# All container images (not just [0])
oc get pods -n openshift-monitoring \
  -l app.kubernetes.io/component=prometheus \
  -o jsonpath='{range .items[*]}{.metadata.name}{":"}{range .spec.containers[*]}{" "}{.image}{end}{"\n"}{end}'

# Pod IP and node, one pod per line
oc get pods -n openshift-monitoring \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.podIP}{"\t"}{.spec.nodeName}{"\n"}{end}'

# Single pod, single field (no range needed)
oc get pod prometheus-k8s-0 -n openshift-monitoring \
  -o jsonpath='{.spec.containers[0].image}{"\n"}'
```

**Gotcha — go-template vs jsonpath:** some docs use `-o go-template=...`. Either works; jsonpath is shorter for typical querying. Don't mix syntaxes — go-template uses `{{ }}` and `range`/`end` from Go's `text/template`.

</details>

---

### Lab 1.3 - Imperative → declarative (15 min)

The "generate YAML, then edit and apply" pattern is the single most useful exam habit. This lab drills it.

**Prerequisites:** a working project. Create one if needed: `oc new-project lab13`.

1. Produce a `web.yaml` file from an imperative command, without creating anything on the cluster.
2. Add a `resources` block (requests/limits).
3. Apply `web.yaml`.
4. Change `replicas` to 4 in two different ways (`oc patch` and `oc edit`).

<details>
<summary>💡 Solution Step 1</summary>

```bash
oc create deployment web \
  --image=quay.io/openshifttest/hello-openshift:1.2.0 \
  --replicas=2 \
  --dry-run=client -o yaml > web.yaml

cat web.yaml
```

You get a complete Deployment manifest:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  creationTimestamp: null
  labels:
    app: web
  name: web
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web
  strategy: {}
  template:
    metadata:
      creationTimestamp: null
      labels:
        app: web
    spec:
      containers:
      - image: quay.io/openshifttest/hello-openshift:1.2.0
        name: hello-openshift
        resources: {}
status: {}
```

**Gotcha — `--dry-run` modes:**

| Mode | Behavior |
|------|----------|
| `--dry-run=client` | Generates YAML locally, never contacts the API server. Use for templating. |
| `--dry-run=server` | Sends the request to the API server in dry-run mode; validates against admission but doesn't persist. |
| `--dry-run=none` (default) | Actually creates the resource. |

For YAML generation, always use `client`.

Other commands that support `--dry-run=client -o yaml`:

```bash
oc create service clusterip web --tcp=80 --dry-run=client -o yaml
oc create route edge web --service=web --dry-run=client -o yaml
oc create configmap app-cm --from-literal=KEY=val --dry-run=client -o yaml
oc create secret generic app-sec --from-literal=PASS=x --dry-run=client -o yaml
oc create role pod-reader --verb=get,list --resource=pods --dry-run=client -o yaml
oc adm policy add-role-to-user view alice --dry-run=client -o yaml
```

Memorize the pattern; you'll use it constantly.

</details>

<details>
<summary>💡 Solution Step 2</summary>

Edit `web.yaml` and replace `resources: {}` with:

```yaml
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
```

The full container block becomes:

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

**Indentation matters.** YAML is 2-space-indented; `resources:` sits at the same level as `image:` and `name:`. If `oc apply` complains, validate first:

```bash
python3 -c "import yaml; yaml.safe_load(open('web.yaml'))" && echo OK
# or let the API server validate without persisting:
oc apply -f web.yaml --dry-run=server
```

</details>

<details>
<summary>💡 Solution Step 3</summary>

```bash
oc apply -f web.yaml
# deployment.apps/web created

oc get deployment web
# NAME   READY   UP-TO-DATE   AVAILABLE   AGE
# web    2/2     2            2           20s

oc get pods -l app=web
# web-xxxxx-yyyyy   1/1   Running   0   25s
# web-xxxxx-zzzzz   1/1   Running   0   25s
```

**Apply vs create vs replace:**

| Command | Idempotent? | Use when |
|---------|-------------|----------|
| `oc create -f x.yaml` | No — errors if the resource already exists | First-time creation, or when you want the error |
| `oc apply -f x.yaml` | Yes — creates or merges with existing | Most everyday use; safe to re-run |
| `oc replace -f x.yaml` | Only for existing resources; errors if not found | Replacing the whole object |

Prefer `oc apply` on the exam unless the task specifically calls for `create` or `replace`.

</details>

<details>
<summary>💡 Solution Step 4</summary>

**Method A — `oc patch`** (scriptable):

```bash
oc patch deployment web -p '{"spec":{"replicas":4}}'
# deployment.apps/web patched
```

`--type` choices:

| Type | What it does |
|------|--------------|
| `strategic` (default) | Kubernetes strategic merge patch — merges lists of known objects (e.g. containers) by their key (`name`) |
| `merge` | JSON merge patch (RFC 7386) — maps merge, but any list you send **replaces** the whole list |
| `json` | JSON patch (RFC 6902) ops (`add`, `remove`, `replace`, …) — needed to touch a specific array index |

**Method B — `oc edit`** (interactive, opens `$EDITOR`):

```bash
oc edit deployment web
# Find `replicas: 2`, change to `replicas: 4`. Save & quit.
# deployment.apps/web edited
```

**Method C (bonus) — `oc scale`** (purpose-built for replicas):

```bash
oc scale deployment/web --replicas=4
# deployment.apps/web scaled
```

`oc scale` is the cleanest for replicas specifically. Knowing all three matters because tasks sometimes say "use a single command" or "without an editor".

Verify:

```bash
oc get deployment web
# NAME   READY   UP-TO-DATE   AVAILABLE   AGE
# web    4/4     4            4           3m
```

**Gotcha:** if you later re-run `oc apply -f web.yaml`, replicas go back to 2 — the file is the source of truth. Update the file too.

Cleanup (optional):

```bash
oc delete -f web.yaml
# or
oc delete project lab13
```

</details>

---

### Lab 1.4 - Break & fix (25 min)

Troubleshooting is a large part of the exam. This lab walks through the most common pod-failure modes and the exact diagnostic commands to use.

**Prerequisites:** a fresh project: `oc new-project lab14`.

1. Deploy an app with a mistyped image tag: `oc new-app --image=quay.io/openshifttest/hello-openshift:does-not-exist`.
2. Use `oc describe` / `oc get events` to identify the cause.
3. Fix it by pointing the Deployment at the correct tag, `1.2.0`.
4. Break it again: scale to 2 replicas and set an impossible CPU request (`resources.requests.cpu: "1000"` — 1000 whole cores). Diagnose with events, then fix.

<details>
<summary>💡 Solution Step 1</summary>

```bash
oc new-app --image=quay.io/openshifttest/hello-openshift:does-not-exist
# warning: cannot use image "...:does-not-exist" ... (the image can't be inspected)
# --> Creating resources ...
#     deployment.apps "hello-openshift" created
# --> Success
```

`oc new-app --image=...` creates a **Deployment** (not a DeploymentConfig), named after the image. Because the image couldn't be inspected, `new-app` doesn't know its ports, so it may not create a Service — that's fine for this lab.

The pod will not start. Confirm:

```bash
oc get pods
# NAME                               READY   STATUS             RESTARTS   AGE
# hello-openshift-xxxxxxxxx-yyyyy    0/1     ImagePullBackOff   0          30s
```

`ImagePullBackOff` means the kubelet keeps retrying the pull and the registry keeps rejecting it.

</details>

<details>
<summary>💡 Solution Step 2</summary>

**Method A — `oc describe pod`:**

```bash
oc describe pod -l deployment=hello-openshift | tail -20
```

(`oc new-app` labels the pods `deployment=<name>`.) Look at the Events section at the bottom:

```text
Events:
  Type     Reason     Age   From               Message
  ----     ------     ----  ----               -------
  Normal   Scheduled  1m    default-scheduler  Successfully assigned lab14/hello-openshift-... to worker-0
  Normal   Pulling    1m    kubelet            Pulling image "quay.io/openshifttest/hello-openshift:does-not-exist"
  Warning  Failed     45s   kubelet            Failed to pull image "...:does-not-exist": ... manifest unknown
  Warning  Failed     45s   kubelet            Error: ErrImagePull
  Normal   BackOff    30s   kubelet            Back-off pulling image "...:does-not-exist"
  Warning  Failed     30s   kubelet            Error: ImagePullBackOff
```

**Method B — `oc get events`** (namespace-wide event log, sorted by time):

```bash
oc get events --sort-by=.lastTimestamp
# or focus on problems:
oc get events --field-selector type=Warning
```

**Method C — `oc describe deployment`** (Deployment-level conditions):

```bash
oc describe deployment hello-openshift | grep -A4 Conditions
# Conditions:
#   Type             Status  Reason
#   ----             ------  ------
#   Available        False   MinimumReplicasUnavailable
#   Progressing      True    ReplicaSetUpdated     (False / ProgressDeadlineExceeded after ~10 min)
```

**Diagnosis triage, in order:**

1. `oc get pods` — what's the status? `ImagePullBackOff` / `CrashLoopBackOff` / `Pending` / `Error` each point to a different category.
2. `oc describe pod <pod>` — read the Events section. Most issues are visible here.
3. `oc logs <pod>` — for `CrashLoopBackOff`, the *previous* container's output is what matters: `oc logs <pod> --previous`.
4. `oc get events --sort-by=.lastTimestamp` — wider context, catches cross-resource issues.

</details>

<details>
<summary>💡 Solution Step 3</summary>

**Method A — `oc set image`** (purpose-built for this):

```bash
# Find the container name first:
oc get deployment hello-openshift -o jsonpath='{.spec.template.spec.containers[*].name}{"\n"}'
# hello-openshift

oc set image deployment/hello-openshift hello-openshift=quay.io/openshifttest/hello-openshift:1.2.0
# deployment.apps/hello-openshift image updated
```

The syntax is `<resource>/<name> <container-name>=<new-image>`.

**Method B — `oc patch`:**

```bash
oc patch deployment hello-openshift --type=json -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/image","value":"quay.io/openshifttest/hello-openshift:1.2.0"}
]'
```

**Method C — `oc edit`:**

```bash
oc edit deployment hello-openshift
# Find spec.template.spec.containers[0].image, fix the tag, save.
```

Verify the fix:

```bash
oc rollout status deployment/hello-openshift
# deployment "hello-openshift" successfully rolled out

oc get pods
# hello-openshift-bbbbbbbbb-ccccc   1/1   Running   0   20s
```

**Variation — a pull that works but a pod that crashes:** try `oc set image deployment/hello-openshift hello-openshift=docker.io/library/nginx:1.27`. The image pulls fine, but it expects to run as root and write to `/var/cache/nginx`. Under the default `restricted-v2` SCC the pod gets a random non-root UID, so it goes into `CrashLoopBackOff` with `Permission denied` in `oc logs --previous`. That's an SCC problem, not a pull problem — see Objective 9 (Lab 9.1). Set the tag back to `hello-openshift:1.2.0` before Step 4.

</details>

<details>
<summary>💡 Solution Step 4</summary>

**Break:**

```bash
oc scale deployment hello-openshift --replicas=2
oc set resources deployment/hello-openshift --requests=cpu=1000
# deployment.apps/hello-openshift resource requirements updated
```

The resource change starts a new rollout. The new ReplicaSet's pod can't be scheduled, and the rolling update keeps the old pods running while it waits:

```bash
oc get pods
# NAME                               READY   STATUS    RESTARTS   AGE
# hello-openshift-xxxxxxxxxx-aaaaa   1/1     Running   0          2m    ← old ReplicaSet, kept by the rolling update
# hello-openshift-xxxxxxxxxx-bbbbb   1/1     Running   0          2m    ← old ReplicaSet
# hello-openshift-yyyyyyyyyy-ccccc   0/1     Pending   0          15s   ← new ReplicaSet, can't schedule
```

**Diagnose** (`oc describe` has no `--field-selector`, so find the Pending pod first):

```bash
oc get pods --field-selector=status.phase=Pending
oc describe pod <pending-pod-name> | tail -10
```

Look for:

```text
Events:
  Warning  FailedScheduling  10s  default-scheduler  0/6 nodes are available:
    6 Insufficient cpu. preemption: 0/6 nodes are available:
    6 No preemption victims found for incoming pod.
```

Key phrase: **`Insufficient cpu`**. The scheduler did the resource math and no node can host this pod.

**Fix** — set a realistic CPU request:

```bash
oc set resources deployment/hello-openshift --requests=cpu=100m
# deployment.apps/hello-openshift resource requirements updated

oc rollout status deployment/hello-openshift
oc get pods
# 2 replicas Running
```

To remove the CPU request entirely instead of changing it:

```bash
oc patch deployment hello-openshift --type=json \
  -p='[{"op":"remove","path":"/spec/template/spec/containers/0/resources/requests/cpu"}]'
```

(`--requests=cpu=0` sets the request to zero; it doesn't remove the field.)

**Other "pod stuck Pending" causes worth knowing:**

| Event message | Cause | Fix |
|---------------|-------|-----|
| `Insufficient cpu` / `Insufficient memory` | Requests exceed any node's free capacity | Lower the request, or add nodes |
| `node(s) had untolerated taint` | Node has a taint the pod doesn't tolerate | Add tolerations, or target other nodes |
| `node(s) didn't match Pod's node affinity/selector` | `nodeSelector` / `nodeAffinity` matches no node | Fix or loosen the selector |
| `volume node affinity conflict` | PV is in a different zone than the nodes the pod can use | Use a `WaitForFirstConsumer` StorageClass, or pin the pod to the volume's zone |
| `pod has unbound immediate PersistentVolumeClaims` | PVC is `Pending` (no matching StorageClass or PV) | Fix the PVC first |

Cleanup:

```bash
oc delete project lab14
```

</details>

---

### Lab 1.5 - Cluster ops sweep (20 min)

A health-check drill. On exam day you want this to take under 5 minutes — the techniques also surface clues for other tasks ("which operator is broken? where's the noisy pod?").

**Prerequisites:**

- Cluster-admin.
- `oc adm top` works only when the monitoring stack is healthy (it usually is on a real cluster; in CRC you may need to wait a few minutes after start).

1. `oc get clusteroperators` — any `AVAILABLE=False` or `DEGRADED=True`?
2. For one operator, run `oc describe co <name>` and read its conditions.
3. Run `oc adm top nodes` and find the most resource-hungry pods cluster-wide.
4. Find the top 5 noisiest pods by log volume.

<details>
<summary>💡 Solution Step 1</summary>

```bash
oc get clusteroperators
# or short form:
oc get co
```

Expected output (truncated):

```text
NAME             VERSION   AVAILABLE   PROGRESSING   DEGRADED   SINCE
authentication   4.18.x    True        False         False      2h
console          4.18.x    True        False         False      2h
dns              4.18.x    True        False         False      2h
etcd             4.18.x    True        False         False      2h
...
```

A healthy cluster has every CO at `AVAILABLE=True`, `PROGRESSING=False`, `DEGRADED=False`.

Quick scan for unhealthy COs:

```bash
oc get co | grep -Ev 'True\s+False\s+False'
# Prints the header and any unhealthy operators
```

Jsonpath probe (for scripting):

```bash
oc get co -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[?(@.type=="Available")].status}{"\t"}{.status.conditions[?(@.type=="Degraded")].status}{"\n"}{end}'
```

**Why start here:** if a cluster operator is degraded, many downstream diagnostics will be misleading. Check `oc get co` first.

</details>

<details>
<summary>💡 Solution Step 2</summary>

Pick any operator (e.g. `authentication`):

```bash
oc describe co authentication | sed -n '/Conditions:/,/Extension:/p'
```

Output structure:

```text
Conditions:
  Last Transition Time:  2026-06-09T12:00:00Z
  Message:               All is well
  Reason:                AsExpected
  Status:                False
  Type:                  Degraded
  Last Transition Time:  2026-06-09T12:00:00Z
  Status:                False
  Type:                  Progressing
  Last Transition Time:  2026-06-09T12:00:00Z
  Status:                True
  Type:                  Available
  Last Transition Time:  2026-06-09T12:00:00Z
  Status:                True
  Type:                  Upgradeable
```

Conditions to know:

| Type | Healthy value | Meaning |
|------|---------------|---------|
| `Available` | `True` | The operator's workload is serving |
| `Progressing` | `False` | The operator isn't mid-rollout |
| `Degraded` | `False` | The operator is functional |
| `Upgradeable` | `True` | The cluster can be upgraded as far as this operator is concerned |
| `EvaluationConditionsDetected` | `False` (or absent) | No unusual conditions detected |

When an operator is degraded, the **Message** field tells you which underlying object failed.

Faster targeted query:

```bash
oc get co authentication -o jsonpath='{range .status.conditions[*]}{.type}={.status}{"\t"}{.message}{"\n"}{end}'
```

</details>

<details>
<summary>💡 Solution Step 3</summary>

Nodes:

```bash
oc adm top nodes
# NAME       CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
# master-0   620m         15%    3500Mi          43%
# worker-0   1200m        30%    8200Mi          51%
# ...
```

Sorted (highest first):

```bash
oc adm top nodes --sort-by=cpu
oc adm top nodes --sort-by=memory
```

Top 10 pods by CPU, cluster-wide (`--sort-by` sorts **descending**, so the biggest are at the top — use `head`, not `tail`):

```bash
oc adm top pods -A --sort-by=cpu | head -11      # header + 10 rows
```

`--sort-by=cpu` is better than a shell `sort` pipe because it understands units (`m`, `Mi`, `Gi`).

Top 10 pods by memory:

```bash
oc adm top pods -A --sort-by=memory | head -11
```

Per-container breakdown:

```bash
oc adm top pods -A --containers --sort-by=memory | head -21
```

**Gotcha — `metrics not available yet`:** the monitoring stack hasn't gathered data. Wait a minute and retry; on a freshly started CRC this can take 3–5 minutes.

</details>

<details>
<summary>💡 Solution Step 4</summary>

"Noisy" here means the most log lines per minute — useful when you suspect a pod is logging an error in a tight loop.

There's no built-in `oc` flag for this, so script it. This samples the last minute of logs across all pods and ranks them:

```bash
oc get pods -A --no-headers \
  -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' \
  | while read ns pod; do
      lines=$(oc logs --since=1m -n "$ns" "$pod" --all-containers 2>/dev/null | wc -l)
      printf "%6d  %s/%s\n" "$lines" "$ns" "$pod"
    done \
  | sort -rn \
  | head -5
```

Quicker smell test — focus on a single namespace:

```bash
for p in $(oc get pods -n openshift-monitoring -o name); do
  printf "%6d  %s\n" "$(oc logs --since=1m -n openshift-monitoring "$p" --all-containers 2>/dev/null | wc -l)" "$p"
done | sort -rn | head -5
```

On the exam, log analysis is usually targeted, not cluster-wide:

```bash
# Last 100 lines, follow live:
oc logs -f deployment/myapp --tail=100

# Previous instance of one container:
oc logs <pod> -c <container> -p

# All containers in one stream:
oc logs <pod> --all-containers=true

# All pods of a deployment (by label):
oc logs -l app=myapp --tail=20 --max-log-requests=10
```

</details>

---

### Lab 1.6 - Cluster update dry-run (CRC) (15 min)

> ℹ️ Cluster updates are taught in the DO280 course but are **not** in the EX280 objective list. Do this lab for understanding; don't over-invest.

This lab is read-mostly. Don't actually upgrade a CRC instance — the time and disk cost are large, and CRC usually has no update service configured, so `oc adm upgrade` may show no recommended updates. The point is to know the commands and what they output.

**Prerequisites:**

- CRC, SNO, or a real cluster with cluster-admin.
- Not the Developer Sandbox — you don't have permission there.

1. Run `oc adm upgrade` — note the current channel and what's available.
2. Switch the channel to `candidate-4.18` (don't actually upgrade).
3. Pause a MachineConfigPool, apply a MachineConfig, then unpause and watch reconciliation.

<details>
<summary>💡 Solution Step 1</summary>

```bash
oc adm upgrade
```

Typical output on a connected, healthy cluster:

```text
Cluster version is 4.18.5

Upstream: https://api.openshift.com/api/upgrades_info/v1/graph
Channel: stable-4.18 (available channels: candidate-4.18, candidate-4.19, eus-4.18, fast-4.18, stable-4.18, stable-4.19)

Recommended updates:

  VERSION   IMAGE
  4.18.6    quay.io/openshift-release-dev/ocp-release@sha256:...
  4.18.7    quay.io/openshift-release-dev/ocp-release@sha256:...
```

Things to read off this output:

- **Channel** — drives which versions are considered:
  - `stable-X.Y` — production-ready patches for the X.Y minor.
  - `fast-X.Y` — patches as soon as they're GA, before they reach stable.
  - `candidate-X.Y` — pre-release, for testing.
  - `eus-X.Y` — Extended Update Support channel, used for EUS-to-EUS updates.
- **Recommended updates** — versions the update graph says you can safely move to from your current version.
- **Not-recommended updates** — reachable, but with known risks; see them with `--include-not-recommended`.

Quick variants:

```bash
oc get clusterversion                                     # condensed view
oc get clusterversion version -o jsonpath='{.spec.channel}{"\n"}{.status.history[0].version}{"\n"}'
oc adm upgrade --include-not-recommended                  # show targets normally hidden
```

</details>

<details>
<summary>💡 Solution Step 2</summary>

```bash
oc adm upgrade channel candidate-4.18
```

Verify the change:

```bash
oc get clusterversion version -o jsonpath='{.spec.channel}{"\n"}'
# candidate-4.18

oc adm upgrade
# Now evaluates candidate-4.18 versions as targets.
```

Roll back:

```bash
oc adm upgrade channel stable-4.18
```

**Channel choice:** generally `stable-X.Y` for the minor you're on; `fast-X.Y` for patches sooner; `candidate-X.Y` only in test clusters; `eus-X.Y` when you're on an EUS release and plan to jump.

**Gotcha — channel name format:** there's no `.z` suffix. `stable-4.18.5` is wrong; the channel covers all z-stream versions of 4.18.

</details>

<details>
<summary>💡 Solution Step 3</summary>

This is the "make a node configuration change with controlled reboot timing" workflow.

Show current MCPs and how many machines each one has:

```bash
oc get mcp
# NAME     CONFIG                    UPDATED   UPDATING   DEGRADED   MACHINECOUNT
# master   rendered-master-abc123    True      False      False      3
# worker   rendered-worker-def456    True      False      False      3
```

> ⚠️ **On CRC/SNO the single node belongs to the `master` pool** and `worker` shows `MACHINECOUNT 0`, so pausing `worker` demonstrates nothing. On those clusters, use `master` in place of `worker` in the commands and YAML below — and expect the node to reboot (a few minutes of API downtime).

Pause the pool:

```bash
oc patch mcp worker --type=merge -p '{"spec":{"paused":true}}'
# machineconfigpool.machineconfiguration.openshift.io/worker patched

oc get mcp worker -o jsonpath='{.spec.paused}{"\n"}'
# true
```

Apply a small MachineConfig that writes a file:

```yaml
# small-mc.yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: worker
  name: 99-worker-test-motd
spec:
  config:
    ignition:
      version: 3.4.0
    storage:
      files:
      - path: /etc/motd
        mode: 0644
        contents:
          source: data:text/plain;charset=utf-8;base64,SGVsbG8gZnJvbSBNQ08K
```

```bash
oc apply -f small-mc.yaml
# machineconfig.machineconfiguration.openshift.io/99-worker-test-motd created
```

Observe that a new rendered config exists but the pool does **not** roll it out while paused:

```bash
oc get mcp worker
# NAME     CONFIG                    UPDATED   UPDATING   DEGRADED
# worker   rendered-worker-def456    False     False      False
#          ^ still the old rendered config; UPDATED=False because a newer one is waiting

oc get mc | grep test-motd
# 99-worker-test-motd  ...
```

Unpause and watch reconciliation:

```bash
oc patch mcp worker --type=merge -p '{"spec":{"paused":false}}'

oc get mcp worker -w
# NAME     CONFIG                    UPDATED   UPDATING   DEGRADED
# worker   rendered-worker-def456    False     True       False     ← rolling
# worker   rendered-worker-NEW...    True      False      False     ← done
```

Each node in the pool is cordoned, drained, rebooted and uncordoned in turn (`maxUnavailable` defaults to 1).

Cleanup:

```bash
oc delete mc 99-worker-test-motd
# The pool rolls AGAIN to remove the file.
```

**Why pausing pools matters:**

- In EUS-to-EUS updates, pausing the worker pool lets the control plane go through the intermediate version without rebooting workers twice.
- It lets you batch several MachineConfig changes into a single reboot.

Reference commands:

```bash
# Which MachineConfigs are merged into the pool's current rendered config:
oc get mcp worker -o jsonpath='{.status.configuration.source[*].name}{"\n"}'

# Is a pool paused?
oc get mcp -o custom-columns=NAME:.metadata.name,PAUSED:.spec.paused
```

</details>

---

## ⚡ Drills (timed, no docs)

| Drill | Target time |
|-------|-------------|
| Log in to a cluster from a fresh shell using a token | 30 s |
| Create a project named exactly `team-alpha-prod` | 15 s |
| Get all pods cluster-wide in `Pending` state | 30 s |
| Get the image of the `installer` container in any pod that has one | 60 s |
| Show the last 5 Warning events across all namespaces | 45 s |
| List the `clusteroperators` whose `Available` condition is False | 30 s |
| Tail-follow logs of every container in `deployment/hello` | 30 s |
| Open a debug shell on a worker node and `chroot /host` | 60 s |

---

## 🔗 Docs links to bookmark

- CLI: <https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/cli_tools/openshift-cli-oc>
- Projects: <https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/building_applications/projects>
- Image streams: <https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/images/managing-image-streams>
- Updates: <https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/updating_clusters/index>
- Troubleshooting: <https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/support/troubleshooting>

---

<div align="center">

[⬅️ Prev: Home](../README.md) &nbsp;·&nbsp; [🏠 Home](../README.md) &nbsp;·&nbsp; [Next: Work with resource manifests ➡️](./02-resource-manifests.md)

</div>
