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
> - Troubleshoot common container, pod, and cluster events and alerts
> - Use product documentation
> - Be prepared to perform all tasks of a Red Hat Certified Technologist in OpenShift

Plus, in 4.18: **be comfortable with cluster updates** (channel selection, EUS-to-EUS, MCP pausing).

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
Service has no endpoints   → oc get endpoints svc/x → labels mismatch between Service.selector and Pod.labels
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

## §9 - OpenShift cluster updates (new emphasis in 4.18 / DO280 v4.18)

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

Prerequisites: logged in as cluster-admin (or any user with self-provisioner). `oc` CLI version close to 4.18.

1. Create a project `lab11`.
2. Show its annotations: `oc get project lab11 -o yaml` - note `openshift.io/requester`.
3. Switch to it and create a pod from `quay.io/openshifttest/hello-openshift:1.2.0`.
4. Delete the project; wait for `Terminating` to finish.

<details>
<summary>💡 Solution Step 1</summary>
bashoc new-project lab11
# Now using project "lab11" on server "https://api.<cluster>:6443".

oc new-project is the user-facing command — it creates the project AND switches your context to it.

Alternative (cluster-admin only):

bashoc create namespace lab11
oc project lab11

The two are not equivalent in OpenShift:


oc new-project goes through the project request API, applies the project template (if one is configured), and sets openshift.io/requester to your username.
oc create namespace bypasses that — no requester annotation, no template processing.


</details>

<details>
<summary>💡 Solution Step 2 </summary>
bashoc get project lab11 -o yaml

Look in the metadata.annotations block. Key entries to recognize:

yamlmetadata:
  annotations:
    openshift.io/description: ""
    openshift.io/display-name: ""
    openshift.io/requester: kubeadmin        # ← who asked for this project
    openshift.io/sa.scc.mcs: s0:c26,c10      # SCC MCS labels
    openshift.io/sa.scc.supplemental-groups: 1000680000/10000
    openshift.io/sa.scc.uid-range: 1000680000/10000

Direct extract via jsonpath:

bashoc get project lab11 -o jsonpath='{.metadata.annotations.openshift\.io/requester}{"\n"}'
# kubeadmin

(Note the \. to escape the dot inside the annotation key.)

Why this matters: openshift.io/requester drives the annotationSelector mode of ClusterResourceQuota — you can build "per-developer quota" rules that auto-attach to every project a given user creates.

</details>

<details>
<summary>💡 Solution Step 3 </summary>
You're already inside lab11 after Step 1. If not:

bashoc project lab11

Create the pod (simplest form):

bashoc run hello --image=quay.io/openshifttest/hello-openshift:1.2.0
# pod/hello created

Verify:

bashoc get pod hello -w
# hello   0/1   ContainerCreating   0   3s
# hello   1/1   Running             0   12s

oc logs hello
# serving on 8080
# serving on 8888

Gotcha — oc run creates a bare Pod, not a Deployment. A bare Pod isn't restarted by a controller if the node fails. On the exam, prefer:

bashoc create deployment hello --image=quay.io/openshifttest/hello-openshift:1.2.0

unless the task explicitly asks for a Pod.

</details>

<details>
<summary>💡 Solution Step 4 </summary>
bashoc delete project lab11
# project.project.openshift.io "lab11" deleted

# Watch the status until the project disappears entirely:
oc get project lab11 -w
# NAME    DISPLAY NAME   STATUS
# lab11                  Terminating
# (... typically 5–20 seconds ...)
# Error from server (NotFound): namespaces "lab11" not found

Alternative — block until deleted (cleaner in scripts):

bashoc delete project lab11 --wait=true

If the project hangs in Terminating forever: there's a stuck finalizer, usually on a custom resource managed by an operator that's no longer running. To diagnose:

bashoc get project lab11 -o json | jq '.spec.finalizers, .metadata.finalizers'
oc get all,pvc,configmap,secret,role,rolebinding -n lab11

Force-removal (use carefully — last resort):

bashoc get project lab11 -o json \
  | jq '.spec.finalizers = [] | .metadata.finalizers = []' \
  | oc replace --raw "/api/v1/namespaces/lab11/finalize" -f -

On the exam, projects normally terminate in seconds. If yours doesn't, suspect a misconfigured operator.

</details>
   
---
### Lab 1.2 - Querying & filtering (15 min)

All four steps target the openshift-monitoring namespace (which always has a healthy set of pods on a real cluster). This lab is muscle memory for the exam - you'll do oc get -o jsonpath and custom-columns repeatedly.

Prerequisites: read access to openshift-monitoring (cluster-admin or cluster-reader works).

In `openshift-monitoring`:

1. List all pods sorted by start time.
2. Show only their names and node names (custom columns).
3. List only pods with label `app.kubernetes.io/component=prometheus`.
4. Get the image of the first container of each prometheus pod (jsonpath).

<details>
<summary>💡Solution Step 1 </summary>
bashoc get pods -n openshift-monitoring --sort-by=.status.startTime

Newest pods are at the bottom. To reverse:

bashoc get pods -n openshift-monitoring --sort-by=.status.startTime | tac

Alternative sort keys you'll want to know:

bashoc get pods -n openshift-monitoring --sort-by=.metadata.creationTimestamp
oc get pods -n openshift-monitoring --sort-by=.status.phase
oc get pods -A --sort-by='.status.containerStatuses[0].restartCount'    # restart troublemakers

Gotcha — --sort-by requires a single JSONPath expression, not the templated {...} form. Don't write --sort-by='{.status.startTime}'.

</details>

<details>
<summary>💡 Solution Step 2 </summary>
bashoc get pods -n openshift-monitoring \
  -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName

Output:

NAME                                          NODE
alertmanager-main-0                           worker-0
prometheus-k8s-0                              worker-1
prometheus-k8s-1                              worker-2
...

Variants worth knowing:

bash# Skip the header (useful in scripts):
oc get pods -n openshift-monitoring \
  -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName --no-headers

# Save the columns spec to a file and reuse:
cat > cols.txt <<EOF
NAME      .metadata.name
NODE      .spec.nodeName
STATUS    .status.phase
EOF
oc get pods -n openshift-monitoring -o custom-columns-file=cols.txt

Gotcha — array indexing in custom columns: for containers[0].image use brackets, not dots:

bashoc get pods -n openshift-monitoring \
  -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image

</details>

<details>
<summary>💡 Solution Step 3 </summary>
bashoc get pods -n openshift-monitoring -l app.kubernetes.io/component=prometheus

Output (typical):

NAME                READY   STATUS    RESTARTS   AGE
prometheus-k8s-0    6/6     Running   0          2d
prometheus-k8s-1    6/6     Running   0          2d

Other selector forms to memorize:

bash# Two labels (AND)
oc get pods -n openshift-monitoring \
  -l app.kubernetes.io/component=prometheus,app.kubernetes.io/instance=k8s

# Label exists (any value)
oc get pods -n openshift-monitoring -l app.kubernetes.io/component

# Label does NOT equal
oc get pods -n openshift-monitoring -l 'app.kubernetes.io/component!=alertmanager'

# Set-based: in / notin
oc get pods -n openshift-monitoring \
  -l 'app.kubernetes.io/component in (prometheus,alertmanager)'

# Negate a label (NOT present)
oc get pods -n openshift-monitoring -l '!app.kubernetes.io/component'

Field selectors (different mechanism, not labels — for status, phase, nodename):

bashoc get pods -A --field-selector=status.phase=Running
oc get pods -A --field-selector=spec.nodeName=worker-0

</details>

<details>
<summary>💡 Solution Step 4 </summary>
bashoc get pods -n openshift-monitoring \
  -l app.kubernetes.io/component=prometheus \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'

Output:

prometheus-k8s-0   quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:...
prometheus-k8s-1   quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:...

Anatomy of the jsonpath expression:

FragmentMeaning{range .items[*]} … {end}iterate over each item in the list{.metadata.name}print the pod's name{"\t"}literal tab{.spec.containers[0].image}image of the first container{"\n"}literal newline

Common variants:

bash# All container images (not just [0])
oc get pods -n openshift-monitoring \
  -l app.kubernetes.io/component=prometheus \
  -o jsonpath='{range .items[*]}{.metadata.name}{":"}{range .spec.containers[*]}{" "}{.image}{end}{"\n"}{end}'

# Pod IP and node, one pod per line
oc get pods -n openshift-monitoring \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.podIP}{"\t"}{.spec.nodeName}{"\n"}{end}'

# Single pod, single field (no range needed)
oc get pod prometheus-k8s-0 -n openshift-monitoring \
  -o jsonpath='{.spec.containers[0].image}{"\n"}'

Gotcha — go-template vs jsonpath: OpenShift docs and oc explain examples sometimes use -o go-template=.... Either works; jsonpath is shorter for typical querying. Don't mix syntaxes — go-template uses {{ }} and range/end from Go's text/template.

</details>

---
### Lab 1.3 - Imperative → declarative (15 min)
The "generate YAML, then edit and apply" pattern is the single most useful exam habit. This lab drills it.

Prerequisites: a working project. Create one if needed: oc new-project lab13.

1. Goal: produce a web.yaml file from an imperative command, without actually creating anything on the cluster. `oc create deployment web --image=quay.io/openshifttest/hello-openshift:1.2.0 --replicas=2 --dry-run=client -o yaml > web.yaml`
2. Add a `resources` block (requests/limits).
3. Patch replicas to 4 using two different methods. Apply web.yaml. `oc apply -f web.yaml`.
4. Patch `replicas` to 4 in two ways: `oc patch` and `oc edit`.

<details>
<summary>💡 Solution Step 1 </summary>
bashoc create deployment web \
  --image=quay.io/openshifttest/hello-openshift:1.2.0 \
  --replicas=2 \
  --dry-run=client -o yaml > web.yaml

cat web.yaml

You get a complete Deployment manifest:

yamlapiVersion: apps/v1
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

Gotcha — --dry-run modes:

ModeBehavior--dry-run=clientGenerates YAML locally, never contacts the API server. Use for templating.--dry-run=serverSends the request to the API server with the dryRun=All flag; validates against admission controllers but doesn't persist.--dry-run=none (default)Actually creates the resource.

For YAML generation always use client.

Other commands that support --dry-run=client -o yaml:

bashoc create service clusterip web --tcp=80 --dry-run=client -o yaml
oc create route edge web --service=web --dry-run=client -o yaml
oc create configmap app-cm --from-literal=KEY=val --dry-run=client -o yaml
oc create secret generic app-sec --from-literal=PASS=x --dry-run=client -o yaml
oc create role pod-reader --verb=get,list --resource=pods --dry-run=client -o yaml
oc adm policy add-role-to-user view alice --dry-run=client -o yaml

Memorize the pattern; you'll use it constantly.

</details>

<details>
<summary>💡 Solution Step 2 </summary>
Edit web.yaml and replace resources: {} with:

yaml        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi

The full container block becomes:

yaml      containers:
      - image: quay.io/openshifttest/hello-openshift:1.2.0
        name: hello-openshift
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi

Indentation matters. YAML is 2-space-indented; the container list items start with -  at the same level as the previous containers: items. If you get an error from oc apply, run it through a linter:

bashpython3 -c "import yaml,sys; yaml.safe_load(open('web.yaml'))" && echo OK
# or
oc apply -f web.yaml --dry-run=server --validate=true

</details>

<details>
<summary>💡 Solution Step 3 </summary>
bashoc apply -f web.yaml
# deployment.apps/web created

oc get deployment web
# NAME   READY   UP-TO-DATE   AVAILABLE   AGE
# web    2/2     2            2           20s

oc get pods -l app=web
# web-xxxxx-yyyyy   1/1   Running   0   25s
# web-xxxxx-zzzzz   1/1   Running   0   25s

Apply vs create:

CommandIdempotent?Use whenoc create -f x.yamlNo — errors if the resource already existsFirst-time creation, or you want the erroroc apply -f x.yamlYes — creates or merges with existingMost everyday use; safe to re-runoc replace -f x.yamlYes for existing resources only; errors if not foundReplacing the whole spec; less merge magic

Prefer oc apply on the exam unless the task specifically calls for create or replace.

</details>

<details>
<summary>💡 Solution Step 4 </summary>
Method A — oc patch (declarative, scriptable):

bashoc patch deployment web --type=merge -p '{"spec":{"replicas":4}}'
# deployment.apps/web patched

--type choices:


merge (default for --type if omitted in some versions) — strategic merge for known fields
strategic — same as merge for most resources; preserves arrays of objects intelligently
json — RFC 6902 ops (add, remove, replace, move, copy); needed for array index manipulation


Method B — oc edit (interactive, opens $EDITOR):

bashoc edit deployment web
# Edit the YAML in vi/vim. Find `replicas: 2`, change to `replicas: 4`. Save & quit.
# deployment.apps/web edited

Method C (bonus) — oc scale (purpose-built for replicas):

bashoc scale deployment/web --replicas=4
# deployment.apps/web scaled

oc scale is the cleanest for replicas specifically. Knowing all three matters because exam tasks sometimes say "use a single command" or "without an editor".

Verify:

bashoc get deployment web
# NAME   READY   UP-TO-DATE   AVAILABLE   AGE
# web    4/4     4            4           3m

Cleanup (optional):

bashoc delete -f web.yaml
# or
oc delete project lab13

</details>

----
### Lab 1.4 - Break & fix (25 min)

Troubleshooting is half the exam. This lab walks through two of the most common pod-failure modes and the exact diagnostic commands to use.

Prerequisites: fresh project: oc new-project lab14.

In a fresh project:

1. Deploy a deliberately broken app with oc new-app --image=nginx:does-not-exist. Deploy `oc new-app --image=nginx:does-not-exist`.
2. Identify the cause with oc describe / oc get events. Use `oc describe` / `oc get events` to identify the cause.
3. Fix by patching the image to `nginx:1.27`.
4. Break it again with an impossible CPU request; Diagnose with events. Fix. Scale to 2, set resources.requests.cpu: "1000" (1000 whole cores - no node can satisfy this).Now break it again by setting `replicas=2` and an impossible `resources.requests.cpu: "1000"`.

<details>
<summary>💡 Solution Step 1 </summary>
bashoc new-app --image=nginx:does-not-exist
# --> Found container image ... (or warning that the image couldn't be inspected)
# --> Creating resources ...
#     deployment.apps "nginx" created
#     service "nginx" created
# --> Success

Note in OCP 4.18: oc new-app --image=... creates a Deployment (not a DeploymentConfig — that was 4.14 behavior).

The pod will not start. Confirm:

bashoc get pods
# NAME                     READY   STATUS             RESTARTS   AGE
# nginx-xxxxxxxxx-yyyyy    0/1     ImagePullBackOff   0          30s

ImagePullBackOff means the kubelet keeps retrying but the image registry rejects each attempt.

</details>

<details>
<summary>💡 Solution Step 2 </summary>
Method A — oc describe pod:

bashoc describe pod -l deployment=nginx | tail -20

Look at the Events section at the bottom. Expect:

Events:
  Type     Reason     Age   From               Message
  ----     ------     ----  ----               -------
  Normal   Scheduled  1m    default-scheduler  Successfully assigned lab14/nginx-... to worker-0
  Normal   Pulling    1m    kubelet            Pulling image "nginx:does-not-exist"
  Warning  Failed     45s   kubelet            Failed to pull image "nginx:does-not-exist": manifest for nginx:does-not-exist not found
  Warning  Failed     45s   kubelet            Error: ErrImagePull
  Normal   BackOff    30s   kubelet            Back-off pulling image "nginx:does-not-exist"
  Warning  Failed     30s   kubelet            Error: ImagePullBackOff

Method B — oc get events (namespace-wide event log, sorted by time):

bashoc get events --sort-by=.lastTimestamp
# or with field selector to focus on errors:
oc get events --field-selector type=Warning

Method C — oc describe deployment (shows Deployment-level conditions):

bashoc describe deployment nginx | tail -20
# Conditions:
#   Type             Status  Reason
#   ----             ------  ------
#   Progressing      False   ProgressDeadlineExceeded
#   Available        False   MinimumReplicasUnavailable

Diagnosis triage in order:


oc get pods — what's the status? ImagePullBackOff / CrashLoopBackOff / Pending / Error each suggest a different category.
oc describe pod <pod> — read the Events section. 80% of issues are visible here.
oc logs <pod> — for CrashLoopBackOff specifically, the previous container's stderr is what matters: oc logs <pod> --previous.
oc get events --sort-by=.lastTimestamp — wider context, catches cross-resource issues.


</details>

<details>
<summary>💡 Solution Step 3 </summary>
Method A — oc set image (purpose-built for this):

bashoc set image deployment/nginx nginx=nginx:1.27
# deployment.apps/nginx image updated

The syntax is <resource>/<name> <container-name>=<new-image>. The container name nginx came from the image name in Step 1; verify with oc get deployment nginx -o jsonpath='{.spec.template.spec.containers[*].name}{"\n"}'.

Method B — oc patch:

bashoc patch deployment nginx --type=json -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/image","value":"nginx:1.27"}
]'

Method C — oc edit:

bashoc edit deployment nginx
# Find spec.template.spec.containers[0].image, change to nginx:1.27, save.

Verify the fix:

bashoc rollout status deployment/nginx
# deployment "nginx" successfully rolled out

oc get pods
# nginx-bbbbbbbbb-ccccc   1/1   Running   0   20s

Gotcha — PSA in 4.18 may reject nginx:1.27: the official nginx image runs as root by default, which violates the restricted Pod Security Admission level enforced on most namespaces in 4.18. If you see:

Warning: would violate PodSecurity "restricted:v1.24": allowPrivilegeEscalation != false ...

…use a rootless image instead:

bashoc set image deployment/nginx nginx=bitnami/nginx:latest
# or
oc set image deployment/nginx nginx=registry.access.redhat.com/ubi9/nginx-122:latest

Both bitnami and Red Hat's UBI nginx images run as non-root.

</details>

<details>
<summary>💡 Solution Step 4 </summary>
Break:

bashoc scale deployment nginx --replicas=2
oc set resources deployment/nginx --requests=cpu=1000
# deployment.apps/nginx resource requirements updated

After a few seconds the new pods will be Pending:

bashoc get pods
# NAME                     READY   STATUS    RESTARTS   AGE
# nginx-xxxxxxxxxx-aaaaa   1/1     Running   0          2m       (old replica from step 3, will eventually be replaced)
# nginx-yyyyyyyyyy-bbbbb   0/1     Pending   0          15s
# nginx-yyyyyyyyyy-ccccc   0/1     Pending   0          15s

Diagnose:

bashoc describe pod -l app=nginx --field-selector=status.phase=Pending | tail -10

Look for:

Events:
  Warning  FailedScheduling  10s  default-scheduler  0/6 nodes are available:
                                     6 Insufficient cpu. preemption: 0/6 nodes are available:
                                     6 No preemption victims found for incoming pod.

Key phrase: Insufficient cpu. The scheduler ran the resource math and concluded no node can host this pod.

Fix - set a realistic CPU request:

bashoc set resources deployment/nginx --requests=cpu=100m
# deployment.apps/nginx resource requirements updated

oc rollout status deployment/nginx
oc get pods
# All 2 replicas Running

To clear the request entirely (revert to "no request"):

bashoc set resources deployment/nginx --requests=cpu=0
# or set both requests AND limits to empty
oc set resources deployment/nginx --requests=cpu=0,memory=0 --limits=cpu=0,memory=0

Other "pod stuck Pending" causes worth knowing:

Event messageCauseFixInsufficient cpu / Insufficient memoryResource requests > any node has freeLower the request, or add nodesnode(s) had untolerated taintNode has a taint your pod doesn't tolerateAdd tolerations, or use a different node selectornode(s) didn't match Pod's node affinity/selectornodeSelector or nodeAffinity matches no nodeLoosen the selector0/N nodes are available, ... volume node affinity conflictPVC bound to a PV in a different AZ than scheduled podRecreate the PVC with WaitForFirstConsumer, or pin the pod to the volume's zone0/N nodes are available, ... pod has unbound immediate PersistentVolumeClaimsPVC is Pending (no SC matches, no PV)Fix the PVC first

Cleanup:

bashoc delete project lab14

</details>

---
### Lab 1.5 - Cluster ops sweep (20 min)

1. `oc get clusteroperators` — any `AVAILABLE=False` or `DEGRADED=True`?
2. For one operator, `oc describe co <name>` and read its conditions.
3. `oc adm top nodes` and `oc adm top pods -A | sort -k4 -h | tail`.
4. Find the top 5 noisiest pods by log volume (`oc logs <pod> | wc -l` for a few candidates).

Lab 1.5 — Cluster ops sweep (20 min)

A health-check drill. On exam day you want this to take under 5 minutes — the techniques here also surface clues for other tasks ("which operator is broken? where's the noisy pod?").

Prerequisites:


Cluster-admin.
oc adm top works only when metrics-server / Prometheus is healthy (it usually is on a real cluster; in CRC you may need to wait a few minutes after start).



Step 1 — oc get clusteroperators — any AVAILABLE=False or DEGRADED=True?

<details>
<summary>💡 Solution</summary>
bashoc get clusteroperators
# or short form:
oc get co

Expected output (truncated):

NAME                                       VERSION   AVAILABLE   PROGRESSING   DEGRADED   SINCE
authentication                             4.18.x    True        False         False      2h
console                                    4.18.x    True        False         False      2h
dns                                        4.18.x    True        False         False      2h
etcd                                       4.18.x    True        False         False      2h
...

A healthy cluster has every CO at: AVAILABLE=True, PROGRESSING=False, DEGRADED=False.

Quick scan for non-healthy COs:

bashoc get co | grep -Ev 'True\s+False\s+False'
# Prints the header and any unhealthy operators

As-jsonpath probe (for scripting):

bashoc get co -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[?(@.type=="Available")].status}{"\t"}{.status.conditions[?(@.type=="Degraded")].status}{"\n"}{end}'

Why this is the right starting point: if any CO is degraded, almost every other diagnostic you run downstream will be misleading. Always check oc get co first.

</details>

Step 2 — oc describe co <name> on one operator and read its conditions

<details>
<summary>💡 Solution</summary>
Pick any operator (e.g., authentication, or whichever is interesting):

bashoc describe co authentication | sed -n '/Conditions:/,/Extension:/p'

Output structure:

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

Five conditions to know:

TypeHealthy valueMeaningAvailableTrueOperator's workload is servingProgressingFalseOperator isn't mid-rolloutDegradedFalseOperator is functionalUpgradeableTrueCluster can be upgraded as far as this operator is concernedEvaluationConditionsDetectedFalse (or absent)No unusual conditions noticed

When an operator is degraded, the Message field is the gold — it tells you exactly which subordinate object failed.

Faster targeted query:

bashoc get co authentication -o jsonpath='{range .status.conditions[*]}{.type}={.status}\t{.message}{"\n"}{end}'

</details>

Step 3 — oc adm top nodes and find the most-resource-hungry pods cluster-wide

<details>
<summary>💡 Solution</summary>
Nodes:

bashoc adm top nodes
# NAME       CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
# master-0   620m         15%    3500Mi          43%
# worker-0   1200m        30%    8200Mi          51%
# ...

Sort by CPU:

bashoc adm top nodes --sort-by=cpu
oc adm top nodes --sort-by=memory

Top 10 pods by CPU (cluster-wide):

bashoc adm top pods -A --sort-by=cpu | tail -10

--sort-by=cpu is preferable to a shell sort -k4 -h pipe because it understands units (m, Mi, Gi).

Top 10 pods by memory:

bashoc adm top pods -A --sort-by=memory | tail -10

Per-container breakdown (more granular):

bashoc adm top pods -A --containers --sort-by=memory | tail -20

Gotcha — metrics not available yet: if oc adm top returns metrics not available yet, the metrics-server (or in OCP's case, the monitoring stack's Prometheus Adapter) hasn't gathered data. Wait 60 seconds after a fresh cluster start and retry. In CRC, this can take 3–5 minutes.

</details>

Step 4 — Find the top 5 noisiest pods by log volume

Definition of "noisy": produces the most log lines per minute. Useful when you suspect a pod is logging an error in a tight loop.

<details>
<summary>💡 Solution</summary>
There's no built-in oc flag for this, so script it. Here's a one-liner that samples the last 1 minute of logs across all pods and ranks them:

bashoc get pods -A --no-headers \
  -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' \
  | while read ns pod; do
      lines=$(oc logs --since=1m -n "$ns" "$pod" --tail=-1 2>/dev/null | wc -l)
      printf "%6d  %s/%s\n" "$lines" "$ns" "$pod"
    done \
  | sort -rn \
  | head -5

Faster (and more pragmatic) approach if you just want a quick smell test — focus on a single noisy namespace:

bashfor p in $(oc get pods -n openshift-monitoring -o name); do
  echo "=== $p ==="
  oc logs --since=1m -n openshift-monitoring "$p" 2>/dev/null | wc -l
done | paste - - - | sort -k2 -rn | head -5

Even more pragmatic — use oc adm node-logs to look at journal-level noise (the systemd journal sees every container's output):

bash# Pick a worker
oc adm node-logs worker-0 --since=1m | head -50

On the exam, log analysis is usually targeted, not cluster-wide:

bash# Last 100 lines, follow live:
oc logs -f deployment/myapp --tail=100

# All containers in a pod:
oc logs -c <container> -p <pod>           # previous container instance
oc logs --all-containers=true <pod>       # all containers in one stream

# All pods of a deployment:
oc logs -l app=myapp --tail=20 --max-log-requests=10

</details>

---
### Lab 1.6 - Cluster update dry-run (CRC) (15 min)

1. `oc adm upgrade` — note current channel & available.
2. `oc adm upgrade channel candidate-4.18` (don't actually upgrade in CRC unless you have time to spare).
3. Pause the `worker` MCP, change a MachineConfig (e.g. add a label), then unpause and watch reconciliation.

Lab 1.6 — Cluster update dry-run (CRC) (15 min)

This lab is read-mostly. Don't actually upgrade a CRC instance — the disk usage and time cost are large. The point is to know the commands and what they output, so on the real exam you can navigate the update flow confidently.

Prerequisites:


CRC, SNO, or a real cluster with cluster-admin.
Do not run this on Developer Sandbox — you don't have permission and the operation would fail loudly.



Step 1 — oc adm upgrade — note the current channel and what's available

<details>
<summary>💡 Solution</summary>
bashoc adm upgrade

Typical output on a healthy cluster:

Cluster version is 4.18.5

Upstream: https://api.openshift.com/api/upgrades_info/v1/graph
Channel: stable-4.18 (available channels: candidate-4.18, candidate-4.19, eus-4.18, fast-4.18, stable-4.18, stable-4.19)

Recommended updates:

  VERSION   IMAGE
  4.18.6    quay.io/openshift-release-dev/ocp-release@sha256:...
  4.18.7    quay.io/openshift-release-dev/ocp-release@sha256:...

Updates with known issues:

  Version: 4.18.4
    Image: quay.io/openshift-release-dev/ocp-release@sha256:...
    Reason: ServiceCABundleInjection
    Message: ...

Three things to read off this output:


Channel — drives which versions are considered for upgrade.

stable-X.Y — production-tested patches for the X.Y minor.
fast-X.Y — patches that have passed soak testing but are newer than stable.
candidate-X.Y — pre-release, for testing.
eus-X.Y — Extended Update Support; long-lived versions to enable EUS-to-EUS jumps.



Recommended updates — versions the upstream graph says you can safely go to from your current version.
Known issues — versions that are reachable in the graph but have caveats; Red Hat is telling you "if you go here, read this first."


Quick variants:

bashoc get clusterversion         # condensed view
oc get clusterversion -o yaml | yq '.spec.channel, .status.history[0]'
oc adm upgrade --include-not-recommended    # show targets normally hidden

</details>

Step 2 — Switch to channel candidate-4.18 (don't actually upgrade)

<details>
<summary>💡 Solution</summary>
bashoc adm upgrade channel candidate-4.18
# Updated the cluster channel to "candidate-4.18"

Verify the change:

bashoc get clusterversion version -o jsonpath='{.spec.channel}{"\n"}'
# candidate-4.18

oc adm upgrade
# Now lists candidate-4.18 versions as recommended targets.

Channel choice matters for the exam: if an exam task says "configure the cluster to receive 4.18 EUS updates", you'd run:

bashoc adm upgrade channel eus-4.18

Channel choice for production: generally stable-X.Y for the X.Y you're on. fast-X.Y if you want patches sooner. candidate-X.Y only in test clusters. eus-X.Y if you're standing on an EUS release and plan to jump.

Roll back:

bashoc adm upgrade channel stable-4.18

Gotcha — channel name format: there's no -z suffix. stable-4.18.5 is wrong; the channel covers all .Z versions inside 4.18.

</details>

Step 3 — Pause the worker MCP, change a MachineConfig, then unpause and watch reconciliation

This is the canonical "make a node configuration change with controlled reboot timing" workflow. On the exam it shows up as "apply this MachineConfig but don't reboot nodes immediately."

<details>
<summary>💡 Solution</summary>
Show current MCPs:

bashoc get mcp
# NAME     CONFIG                                              UPDATED   UPDATING   DEGRADED
# master   rendered-master-abc123...                           True      False      False
# worker   rendered-worker-def456...                           True      False      False

Pause the worker MCP:

bashoc patch mcp worker --type=merge -p '{"spec":{"paused":true}}'
# machineconfigpool.machineconfiguration.openshift.io/worker patched

oc get mcp worker -o jsonpath='{.spec.paused}{"\n"}'
# true

Apply a trivial MachineConfig change — for the dry-run, add a label to nodes via the MCP (no reboot needed) or write a small file via MachineConfig:

yaml# small-mc.yaml
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

bashoc apply -f small-mc.yaml
# machineconfig.machineconfiguration.openshift.io/99-worker-test-motd created

Observe that the MCO rendered a new config but did NOT apply it (because the MCP is paused):

bashoc get mcp worker
# NAME     CONFIG                                              UPDATED   UPDATING   DEGRADED
# worker   rendered-worker-def456...                           True      False      False
#          ^ still the old rendered config; not rolling

bashoc get mc | grep test-motd
# 99-worker-test-motd  ...

Unpause and watch reconciliation:

bashoc patch mcp worker --type=merge -p '{"spec":{"paused":false}}'

# Watch the rollout:
oc get mcp worker -w
# NAME     CONFIG                                              UPDATED   UPDATING   DEGRADED
# worker   rendered-worker-def456...                           False     True       False     ← rolling
# worker   rendered-worker-NEW...                              True      False      False    ← done

Each worker node will cordon, drain, reboot, and uncordon serially. On CRC (single-node), the node will reboot — expect a 2–3 minute outage of the kubelet during the reboot.

Cleanup:

bashoc delete mc 99-worker-test-motd
# Workers will roll AGAIN to remove the file. If you don't want that, leave it.

Why pausing MCPs is critical knowledge for 4.18 exam:


EUS-to-EUS upgrades require pausing the worker MCP so workers don't reboot until you tell them to.
During cluster upgrades, controlling reboots is essential for workload availability.
Day-2 ops like rotating ignition certs go through this exact mechanism.


Reference command set:

bash# Pause all worker pools (if you have multiple):
for mcp in $(oc get mcp -o jsonpath='{range .items[?(@.metadata.labels.machineconfiguration\.openshift\.io/mco-built-in!="")]}{.metadata.name}{" "}{end}'); do
  oc patch mcp $mcp --type=merge -p '{"spec":{"paused":true}}'
done

# Unpause:
oc patch mcp worker --type=merge -p '{"spec":{"paused":false}}'

# Check which MCs are merged into the current rendered config:
oc get mcp worker -o jsonpath='{.status.configuration.source[*].name}{"\n"}'

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
