<div align="center">

[⬅️ Prev: Work with resource manifests](./02-resource-manifests.md) &nbsp;·&nbsp; [🏠 Home](../README.md) &nbsp;·&nbsp; [Next: Authentication & authorization ➡️](./04-auth-and-authorization.md)

</div>

# Objective 3 - Deploy Applications

> **Exam study points:**
> - Deploy applications from templates and Helm charts
> - Manage application deployments
> - Work with replica sets
> - Work with labels and selectors
> - Configure services
> - Expose applications to external access


## §1 - `oc new-app`: the Swiss army knife

`oc new-app` is OpenShift's one-liner for deploying. In **4.18 it creates a `Deployment`** (not a deprecated `DeploymentConfig`) by default.

```bash
# From a container image
oc new-app --image=quay.io/openshifttest/hello-openshift:1.2.0 --name=hello

# From a Git repo (Source-to-Image / S2I picks the right builder)
oc new-app --name=nodejs https://github.com/sclorg/nodejs-ex.git

# From a Git repo + specific builder image stream
# (list available tags first: oc get is nodejs -n openshift -o jsonpath='{.spec.tags[*].name}')
oc new-app --image-stream=openshift/nodejs:20-ubi9 \
  --code=https://github.com/sclorg/nodejs-ex.git --name=nodejs

# From a Dockerfile in a Git repo
oc new-app https://github.com/openshift/ruby-hello-world.git --strategy=docker --name=ruby-hello

# With env, labels, and a different namespace
oc new-app --image=registry.redhat.io/rhel9/mysql-80:latest --name=mysql \
  -e MYSQL_USER=app -e MYSQL_PASSWORD=app -e MYSQL_DATABASE=appdb \
  -l app=mysql,tier=db -n myapp

# See what new-app would create *before* it does
oc new-app --image=nginx --dry-run -o yaml
```

### Inspect / clean up what `oc new-app` made

```bash
oc status                            # textual summary of the project
oc get all -l app=hello              # everything new-app labels with the same selector
oc delete all -l app=hello           # tear it all down
```

## §2 - Templates

A `Template` is a parameterized bundle of resources that lives in the cluster (often in the `openshift` namespace).

```bash
# Discover available templates
oc get templates -n openshift
oc describe template mysql-persistent -n openshift

# See its parameters
oc process --parameters mysql-persistent -n openshift

# Render with parameters (no apply)
oc process mysql-persistent -n openshift -p MYSQL_USER=app -p MYSQL_PASSWORD=app -p MYSQL_DATABASE=appdb

# Render + apply
oc process mysql-persistent -n openshift \
  -p MYSQL_USER=app -p MYSQL_PASSWORD=app -p MYSQL_DATABASE=appdb \
  | oc apply -f -

# new-app also accepts templates directly
oc new-app --template=mysql-persistent -p MYSQL_USER=app -p MYSQL_PASSWORD=app -p MYSQL_DATABASE=appdb
```

### Authoring a Template

```yaml
apiVersion: template.openshift.io/v1
kind: Template
metadata:
  name: hello-template
  annotations:
    description: "Deploy a hello-openshift app"
parameters:
  - name: APP_NAME
    description: Application name
    required: true
    value: hello
  - name: REPLICAS
    value: "2"
  - name: IMAGE
    value: quay.io/openshifttest/hello-openshift:1.2.0
objects:
  - apiVersion: apps/v1
    kind: Deployment
    metadata: { name: "${APP_NAME}", labels: { app: "${APP_NAME}" } }
    spec:
      replicas: "${{REPLICAS}}"          # ${{…}} = numeric/bool, ${…} = string
      selector: { matchLabels: { app: "${APP_NAME}" } }
      template:
        metadata: { labels: { app: "${APP_NAME}" } }
        spec:
          containers:
            - name: app
              image: "${IMAGE}"
              ports: [{ containerPort: 8080 }]
  - apiVersion: v1
    kind: Service
    metadata: { name: "${APP_NAME}" }
    spec:
      selector: { app: "${APP_NAME}" }
      ports: [{ port: 8080, targetPort: 8080 }]
```

Save the template into the cluster: `oc apply -f hello-template.yaml -n myapp`, then `oc process` / `oc new-app --template=hello-template`.

## §3 - Helm charts

Helm 3 is a client-only tool (no Tiller). Download the `helm` binary from the web console (**?** → *Command Line Tools*) if it isn't installed.

```bash
# Add a chart repo (on the exam, use the repo URL the task gives you)
helm repo add openshift-helm-charts https://charts.openshift.io/
helm repo update
helm search repo openshift-helm-charts            # list charts
helm search repo openshift-helm-charts/<chart> --versions

# Look before you install
helm show chart  <repo>/<chart>
helm show values <repo>/<chart> > values.yaml      # every setting you can override

# Install (in the current namespace)
helm install myrel <repo>/<chart> --set key=value     # or -f my-values.yaml
helm install myrel <repo>/<chart> --version 1.2.3     # pin a chart version

# Inspect
helm list                  # releases in this namespace (-A for all)
helm status myrel
helm get values myrel      # only YOUR overrides (--all for everything)
helm history myrel

# Upgrade & rollback
helm upgrade myrel <repo>/<chart> --reuse-values --set key=newvalue
helm rollback myrel 1      # back to revision 1 (creates a NEW revision)

# Uninstall
helm uninstall myrel
```

> ⚠️ **Avoid the public Bitnami charts for practice.** Broadcom archived the free `docker.io/bitnami` images in September 2025, so those charts no longer pull. Use a chart from `charts.openshift.io`, or build your own with `helm create` (Lab 3.4).

> **Charts and OpenShift security:** many upstream charts assume they can run as root or as a fixed UID. Under the default `restricted-v2` SCC those pods crash. Prefer charts and images built for OpenShift (UBI-based, arbitrary UID).

### Helm in OpenShift specifics

OCP exposes Helm via the **HelmChartRepository** CRD (cluster-scoped) and **ProjectHelmChartRepository** (namespace-scoped).

```yaml
apiVersion: helm.openshift.io/v1beta1
kind: ProjectHelmChartRepository
metadata:
  name: my-team-repo
  namespace: myapp
spec:
  connectionConfig:
    url: https://charts.example.com
  name: my-team-repo
```

Apply it and the repo's charts appear in the web console's Helm catalog. Where that is depends on the console version: **Developer → +Add → Helm Chart** in 4.18 (when the Developer perspective is enabled), **Ecosystem → Helm** in 4.22.

## §4 - Deployments, ReplicaSets, labels & selectors

A `Deployment` manages a `ReplicaSet`, which manages `Pods`. **Selectors are mandatory** and must match the pod template's labels.

```yaml
spec:
  replicas: 3
  selector:
    matchLabels:
      app: hello
      tier: frontend
  template:
    metadata:
      labels:                  # MUST be a superset of selector.matchLabels
        app: hello
        tier: frontend
        version: v1
```

### Scaling

```bash
# Manual
oc scale deployment/hello --replicas=4

# Conditional (only if currently 3)
oc scale deployment/hello --replicas=4 --current-replicas=3

# Horizontal Pod Autoscaler (HPA)
oc autoscale deployment/hello --min=2 --max=10 --cpu-percent=70
oc get hpa
```

### Label / annotate

```bash
oc label deployment hello team=alpha
oc label deployment hello team-                       # remove
oc annotate deployment hello description='EX280 demo'

# Bulk-select
oc get all -l team=alpha
oc delete all -l team=alpha
```

### Rollouts

```bash
oc rollout status deployment/hello
oc rollout history deployment/hello
oc rollout undo deployment/hello
oc rollout pause deployment/hello
oc rollout resume deployment/hello
oc rollout restart deployment/hello                   # forces new ReplicaSet, useful after Secret/CM change
```

## §5 - Services

A `Service` is a stable virtual IP + DNS name in front of pods matching a selector.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: hello
spec:
  type: ClusterIP             # default; cluster-internal only
  selector:
    app: hello
  ports:
    - name: http
      port: 80                # the Service port
      targetPort: 8080        # the pod containerPort (number or name)
      protocol: TCP
```

### Service types

| Type | Use |
|------|-----|
| `ClusterIP` | Internal-only; the default. Pair with a Route to expose externally. |
| `NodePort` | Exposes a port (30000-32767) on every node. Used for non-HTTP/SNI traffic (Obj 6). |
| `LoadBalancer` | Cloud LB; auto-allocates external IP. Also Obj 6. |
| `ExternalName` | DNS alias to an out-of-cluster name. |
| Headless (`clusterIP: None`) | Returns A records for each pod; used by StatefulSets. |

### Imperative shortcuts

```bash
# Service from a deployment's selector
oc expose deployment/hello --port=80 --target-port=8080 --name=hello

# Verify endpoints
oc get svc hello
oc get endpointslices -l kubernetes.io/service-name=hello
oc get endpoints hello       # older API — still works, but deprecated from OCP 4.20 (prints a warning)
oc describe svc hello        # the "Endpoints:" line
```

> ❗ **Endpoints empty?** Either the Service `selector` doesn't match any pod's labels, or the matching pods aren't **Ready** (failing readiness probe — they show up as not-ready in the EndpointSlice). Compare `oc get svc hello -o jsonpath='{.spec.selector}'` with `oc get pods --show-labels`. Usually you fix the Service selector — a Deployment's own selector is immutable.

## §6 - Exposing apps externally with Routes

Routes are OpenShift's ingress for HTTP/HTTPS. Powered by HAProxy in the `openshift-ingress` namespace.

```bash
# Simple HTTP route
oc expose svc/hello                                           # uses default subdomain
oc expose svc/hello --hostname=hello.apps.example.com
```

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: hello
spec:
  host: hello.apps.example.com           # optional; auto-generated otherwise
  to:
    kind: Service
    name: hello
    weight: 100
  port:
    targetPort: 8080
```

### TLS-terminated routes - see Objective 5 in detail

```bash
# Edge: TLS terminated at the router; cleartext to pod
oc create route edge hello --service=hello \
  --cert=server.crt --key=server.key --ca-cert=ca.crt \
  --hostname=hello.apps.example.com

# Passthrough: TLS passes straight to the pod (pod handles cert)
oc create route passthrough hello --service=hello-https

# Re-encrypt: router decrypts with cert, re-encrypts to the pod
oc create route reencrypt hello --service=hello-https \
  --cert=server.crt --key=server.key --ca-cert=ca.crt \
  --dest-ca-cert=pod-ca.crt
```

### Get a route's URL

```bash
oc get route hello -o jsonpath='{.spec.host}'
curl -sk https://$(oc get route hello -o jsonpath='{.spec.host}')
```

---

## 🧪 Labs

### Lab 3.1 - Five flavors of new-app (25 min)

In project `lab31`, run `oc new-app` five times with five different sources:

1. Direct image (`hello-openshift`)
2. Git + S2I (`nodejs-ex`)
3. From a template (`mysql-persistent`)
4. From a Dockerfile in Git (`--strategy=docker`)
5. From an explicit builder image stream + code: `--image-stream=openshift/python:<tag> --code=…`

For each, run `oc status` and look at what got created.

> ℹ️ Flavors 2, 4 and 5 run **builds**, so the cluster needs internet access to GitHub and the Build capability enabled (it can be disabled at install time). Flavor 3 needs a default StorageClass for its PVC.

<details>
<summary>💡 Solution 1 — direct image</summary>

```bash
oc new-project lab31

oc new-app --image=quay.io/openshifttest/hello-openshift:1.2.0 --name=hello
# --> Creating resources ...
#     deployment.apps "hello" created
#     service "hello" created

oc get all -l app=hello
```

`new-app` inspected the image, saw it exposes ports 8080/8888, and created a Service for them. It labels everything `app=hello`, which is why `oc get all -l app=hello` / `oc delete all -l app=hello` work.

</details>

<details>
<summary>💡 Solution 2 — Git + S2I</summary>

```bash
oc new-app https://github.com/sclorg/nodejs-ex.git --name=nodejs
# --> Found image ... "openshift/nodejs" ... (detected from package.json)
#     imagestream.image.openshift.io "nodejs" created
#     buildconfig.build.openshift.io "nodejs" created
#     deployment.apps "nodejs" created
#     service "nodejs" created

oc logs -f bc/nodejs          # follow the S2I build
oc get builds
oc get pods -l deployment=nodejs
```

S2I detected Node.js from `package.json`. The chain is: BuildConfig → Build → image pushed to the internal registry → ImageStream tag updated → Deployment rolls out the new image.

</details>

<details>
<summary>💡 Solution 3 — from a template</summary>

```bash
oc get templates -n openshift | grep mysql
oc process --parameters mysql-persistent -n openshift      # what can I set?

oc new-app --template=mysql-persistent \
  -p MYSQL_USER=app -p MYSQL_PASSWORD=app -p MYSQL_DATABASE=appdb \
  -p VOLUME_CAPACITY=1Gi

oc status
oc get pvc
oc get deploy,dc        # older sample templates still create a DeploymentConfig
```

Templates carry their own labels (check with `oc get all --show-labels`), so `-l app=…` may not match. `oc status` is the quickest overview.

The sample templates come from the Cluster Samples Operator, which is deprecated; if `oc get templates -n openshift` is empty, the operator has been removed on your cluster — use Lab 3.2's own template instead.

</details>

<details>
<summary>💡 Solution 4 — Dockerfile in Git</summary>

```bash
oc new-app https://github.com/openshift/ruby-hello-world.git --strategy=docker --name=ruby-hello

oc logs -f bc/ruby-hello
oc get bc ruby-hello -o jsonpath='{.spec.strategy.type}{"\n"}'
# Docker
```

`--strategy=docker` builds from the repo's `Dockerfile` instead of using an S2I builder. (`--strategy=source` forces S2I.)

</details>

<details>
<summary>💡 Solution 5 — explicit builder image stream + code</summary>

```bash
# Which python versions does this cluster offer?
oc get is python -n openshift -o jsonpath='{range .spec.tags[*]}{.name}{"\n"}{end}'

oc new-app --image-stream=openshift/python:3.11-ubi9 \
  --code=https://github.com/sclorg/django-ex.git#4.2.x --name=django

oc logs -f bc/django
```

`#4.2.x` selects a Git branch: the repo's default branch now only holds a README pointing to per-version branches (`4.2.x` = Django 4.2 LTS, which supports Python 3.11), so building it would fail.

Use this form when auto-detection picks the wrong builder or version. The shorthand is `oc new-app python:3.11-ubi9~https://github.com/sclorg/django-ex.git#4.2.x`.

**Wrap-up for all five:**

```bash
oc status                     # the whole project, with build/deploy links
oc get all                    # deployments, replicasets, pods, services, builds, imagestreams
oc delete project lab31
```

</details>

### Lab 3.2 - Author and use a Template (25 min)

1. Save the `hello-template` from §2 as a YAML.
2. `oc apply -f hello-template.yaml -n openshift` (note: needs cluster-admin).
3. From a regular user in project `lab32`, `oc new-app --template=hello-template -p APP_NAME=greeter -p REPLICAS=3`.
4. Verify the resulting Deployment + Service.

<details>
<summary>💡 Solution</summary>

**Steps 1–2 (as cluster-admin):**

```bash
# hello-template.yaml = the Template from §2
oc apply -f hello-template.yaml -n openshift
oc get template hello-template -n openshift

# Check what it does before anyone uses it:
oc process --parameters hello-template -n openshift
oc process hello-template -n openshift -p APP_NAME=test | head -30
```

Templates in the `openshift` namespace are readable by every authenticated user — that's what makes them a shared catalog.

**Step 3 (as a regular user):**

```bash
oc login -u alice -p <password>
oc new-project lab32

oc new-app --template=hello-template -p APP_NAME=greeter -p REPLICAS=3
# --> Deploying template "openshift/hello-template" for "hello-template" to project lab32
#     deployment.apps "greeter" created
#     service "greeter" created
```

`new-app` looks for the template in the current project first, then in `openshift`. The equivalent long form is:

```bash
oc process openshift//hello-template -p APP_NAME=greeter -p REPLICAS=3 | oc apply -f -
```

**Step 4:**

```bash
oc get deployment greeter -o jsonpath='{.spec.replicas}{"\n"}'
# 3          ← a number, thanks to ${{REPLICAS}}

oc get svc greeter
oc get endpointslices -l kubernetes.io/service-name=greeter    # 3 addresses
```

**Gotcha:** with `replicas: "${REPLICAS}"` (single braces) the value would be the string `"3"` and the Deployment would be rejected. `${{…}}` substitutes the raw value.

Cleanup: `oc delete project lab32`, and as admin `oc delete template hello-template -n openshift`.

</details>

### Lab 3.3 - Service & Route end-to-end (20 min)

1. Deploy `quay.io/openshifttest/hello-openshift:1.2.0` (3 replicas).
2. Expose port 8080 as a `ClusterIP` Service named `hello`.
3. `curl` it from another pod (`oc run tmp --image=registry.access.redhat.com/ubi9/ubi-minimal -i --rm --restart=Never -- curl -s http://hello:8080`).
4. Create an HTTP Route and `curl` it from your workstation.
5. **Break** it by changing the Service's selector so it matches no pods; observe the empty endpoints; fix.

<details>
<summary>💡 Solution Steps 1–3</summary>

```bash
oc new-project lab33

oc create deployment hello --image=quay.io/openshifttest/hello-openshift:1.2.0 --replicas=3
oc expose deployment hello --port=8080 --name=hello
# service/hello exposed   (type ClusterIP by default)

oc get svc hello
oc get endpointslices -l kubernetes.io/service-name=hello
# 3 pod IPs on port 8080

oc run tmp --image=registry.access.redhat.com/ubi9/ubi-minimal -i --rm --restart=Never -- \
  curl -s http://hello:8080
# Hello OpenShift!
```

The short name `hello` resolves because `tmp` runs in the same namespace. From another namespace you'd use `hello.lab33.svc` (or the full `hello.lab33.svc.cluster.local`).

</details>

<details>
<summary>💡 Solution Step 4</summary>

```bash
oc expose service hello
oc get route hello
curl -s http://$(oc get route hello -o jsonpath='{.spec.host}')
# Hello OpenShift!
```

</details>

<details>
<summary>💡 Solution Step 5</summary>

**Break** — point the Service at a label no pod has:

```bash
oc patch service hello -p '{"spec":{"selector":{"app":"nope"}}}'

oc get endpointslices -l kubernetes.io/service-name=hello
# ENDPOINTS: <unset>     ← nothing matches
curl -s -o /dev/null -w '%{http_code}\n' http://$(oc get route hello -o jsonpath='{.spec.host}')
# 503
```

**Diagnose** — compare the selector with the pod labels:

```bash
oc get svc hello -o jsonpath='{.spec.selector}{"\n"}'
# {"app":"nope"}
oc get pods --show-labels
# ... app=hello,pod-template-hash=...
```

**Fix:**

```bash
oc patch service hello -p '{"spec":{"selector":{"app":"hello"}}}'
oc get endpointslices -l kubernetes.io/service-name=hello      # 3 addresses again
curl -s http://$(oc get route hello -o jsonpath='{.spec.host}')
```

**Why break the Service and not the Deployment:** a Deployment's `spec.selector` is immutable, and its pod template labels must keep matching that selector — so you can't easily "unmatch" from the Deployment side. Real-world mismatches usually come from a Service written by hand with a typo'd label.

Cleanup: `oc delete project lab33`

</details>

### Lab 3.4 - Helm install + values (25 min)

The public Bitnami charts no longer work (their images were archived in 2025), so this lab uses a chart you create yourself — which also teaches you what a chart actually contains.

1. In project `lab34`, create a chart `web` with `helm create` and make it run `quay.io/openshifttest/hello-openshift:1.2.0` on port 8080.
2. Install it as release `web` with 2 replicas and a `ClusterIP` Service.
3. Create a Route to the Helm-managed Service.
4. Upgrade to 3 replicas: `helm upgrade web ./web --reuse-values --set replicaCount=3`.
5. Roll back to revision 1. Confirm replicas are back to 2.

<details>
<summary>💡 Solution Step 1</summary>

```bash
oc new-project lab34
helm create web
ls web
# Chart.yaml  charts/  templates/  values.yaml
```

The starter chart deploys upstream `nginx` on port 80, which wants to run as root and crashes under OpenShift's `restricted-v2` SCC. Point it at an image that runs as any UID and serves HTTP 200 on `/` port 8080 (the chart's liveness/readiness probes hit `/`):

```bash
# Check how the template wires the port (Helm 3.16 uses .Values.service.port):
grep -n containerPort web/templates/deployment.yaml
#   containerPort: {{ .Values.service.port }}
```

If your Helm version prints a hardcoded `containerPort: 80` instead, change it to `{{ .Values.service.port }}`.

Write your overrides to a values file (easier to read and reuse than many `--set` flags):

```yaml
# web-values.yaml
replicaCount: 2
image:
  repository: quay.io/openshifttest/hello-openshift
  tag: "1.2.0"
service:
  type: ClusterIP
  port: 8080
```

Check the render before installing:

```bash
helm lint ./web -f web-values.yaml
helm template web ./web -f web-values.yaml | grep -E 'image:|containerPort|replicas|type:'
```

</details>

<details>
<summary>💡 Solution Step 2</summary>

```bash
helm install web ./web -f web-values.yaml
# NAME: web
# STATUS: deployed
# REVISION: 1

helm list
oc get deploy,svc,pods
# deployment.apps/web   2/2
# service/web           ClusterIP   ...   8080/TCP
```

The release name `web` contains the chart name, so resources are named just `web` (otherwise they'd be `<release>-<chart>`).

</details>

<details>
<summary>💡 Solution Step 3</summary>

```bash
oc expose service web
curl -s http://$(oc get route web -o jsonpath='{.spec.host}')
# Hello OpenShift!
```

The Route isn't part of the release, so `helm uninstall` won't remove it. (The chart's `ingress:` values could create an Ingress instead, which OpenShift turns into a Route.)

</details>

<details>
<summary>💡 Solution Step 4</summary>

```bash
helm upgrade web ./web --reuse-values --set replicaCount=3
# REVISION: 2

oc get deploy web -o jsonpath='{.spec.replicas}{"\n"}'
# 3
helm get values web
# replicaCount: 3  (plus the other overrides)
```

**Gotcha — `--reuse-values`:** without it (and without `-f web-values.yaml`), `helm upgrade` starts from the chart defaults again and you'd silently lose the image and port overrides. Either pass `--reuse-values` or pass your values file on every upgrade.

</details>

<details>
<summary>💡 Solution Step 5</summary>

```bash
helm history web
# REVISION  STATUS      DESCRIPTION
# 1         superseded  Install complete
# 2         deployed    Upgrade complete

helm rollback web 1
# Rollback was a success!

oc get deploy web -o jsonpath='{.spec.replicas}{"\n"}'
# 2
helm history web
# 3         deployed    Rollback to 1     ← a rollback is recorded as a new revision
```

**Practice the repo workflow too** (closer to what an exam task looks like — "install chart X from repo URL Y"):

```bash
helm repo add openshift-helm-charts https://charts.openshift.io/
helm search repo openshift-helm-charts | head
helm show values openshift-helm-charts/<chart>
```

Cleanup:

```bash
helm uninstall web
oc delete project lab34
```

</details>

---

## ⚡ Drills (timed, no docs)

| Drill | Target time |
|-------|-------------|
| Deploy an image with `oc new-app` and expose it via Route | 60 s |
| Scale a deployment to 7 replicas | 15 s |
| Set an env var on a deployment from a Secret key | 30 s |
| Find the Service whose endpoints are empty and fix it | 90 s |
| Install a Helm chart and uninstall it | 45 s |
| Render a Template with 3 parameters and pipe to `oc apply` | 60 s |

---

## ❗ Common pitfalls

1. **`DeploymentConfig` vs `Deployment`** - older repos/docs use DC; DC is deprecated since 4.14, so use Deployment. DCs still run, but some commands differ (`oc rollout latest dc/<name>` etc.).
2. **`oc expose svc/<x>` creates a route**, but `oc expose deployment/<x>` creates a Service. Be explicit.
3. **Template numeric params** need the `${{PARAM}}` syntax (double-brace) to come through as int/bool - `${PARAM}` always stringifies.
4. **Helm releases are per-namespace**, but CRDs installed by a chart are cluster-scoped - uninstalling the release may leave them around.
5. **`helm upgrade` without `--reuse-values` or `-f`** resets every override you set at install time.
6. **Charts built for vanilla Kubernetes** often assume root or a fixed UID and crash under `restricted-v2`. Check `oc logs` / `oc get events` before blaming the chart values.

---

## 🔗 Docs to bookmark

Swap `4.18` for your exam's version. If a page 404s, open the guide's `index` page and use the left-hand navigation.

- Building applications (projects, `new-app`, Deployments, quotas): <https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/building_applications/index>
- Working with Helm charts: <https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/building_applications/working-with-helm-charts>
- Images (image streams, templates): <https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/images/index>
- Routes (*Ingress and load balancing* guide — since 4.18 networking is split into several guides): <https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/ingress_and_load_balancing/routes>

---

<div align="center">

[⬅️ Prev: Work with resource manifests](./02-resource-manifests.md) &nbsp;·&nbsp; [🏠 Home](../README.md) &nbsp;·&nbsp; [Next: Authentication & authorization ➡️](./04-auth-and-authorization.md)

</div>
