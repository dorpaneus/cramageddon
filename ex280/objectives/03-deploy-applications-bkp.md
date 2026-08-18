# Objective 3 — Deploy Applications

> **Exam study points:**
> - Deploy applications from templates and Helm charts
> - Manage application deployments
> - Work with replica sets
> - Work with labels and selectors
> - Configure services
> - Expose applications to external access

---

## §1 — `oc new-app`: the Swiss army knife

`oc new-app` is OpenShift's one-liner for deploying. In **4.18 it creates a `Deployment`** (not a deprecated `DeploymentConfig`) by default.

```bash
# From a container image
oc new-app --image=quay.io/openshifttest/hello-openshift:1.2.0 --name=hello

# From a Git repo (Source-to-Image / S2I picks the right builder)
oc new-app --name=nodejs https://github.com/sclorg/nodejs-ex.git

# From a Git repo + specific builder image stream
oc new-app --image-stream=openshift/nodejs:18-ubi9 \
  --code=https://github.com/sclorg/nodejs-ex.git --name=nodejs

# From a Dockerfile in a Git repo
oc new-app https://github.com/sclorg/nginx-ex.git --strategy=docker

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

## §2 — Templates

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

## §3 — Helm charts

Helm 3 ships natively. No Tiller.

```bash
# Add a chart repo
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm search repo mysql

# Install (in current namespace)
helm install mydb bitnami/mysql --set auth.rootPassword=hunter2

# Inspect
helm list
helm status mydb
helm get values mydb

# Upgrade & rollback
helm upgrade mydb bitnami/mysql --set auth.rootPassword=newpass
helm rollback mydb 1

# Uninstall
helm uninstall mydb
```

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

Apply and the repo appears in the web console **Developer → +Add → Helm Chart**.

## §4 — Deployments, ReplicaSets, labels & selectors

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

## §5 — Services

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
oc get endpoints hello
oc describe svc hello
```

> ❗ **Endpoints empty?** Always means the Service `selector` doesn't match any pod labels. Fix the labels, not the Service.

## §6 — Exposing apps externally with Routes

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

### TLS-terminated routes — see Objective 5 in detail

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

### Lab 3.1 — Five flavors of new-app (25 min)

`oc new-app` accepts many source types. Knowing which flavor produces what (and when S2I builds kick in) is exactly the kind of thing the exam probes. Run each and inspect the resulting objects.

**Prerequisites:**
- Project: `oc new-project lab31`.
- For the Git/S2I flavors, the cluster needs build capability and egress to the Git host. On air-gapped/Sandbox environments some of these will fail — that's fine, focus on the image and template flavors which always work.

---

#### Flavor 1 — Direct image

<details>
<summary>💡 Solution</summary>

```bash
oc new-app --image=quay.io/openshifttest/hello-openshift:1.2.0 --name=direct
# --> Found container image ...
# --> Creating resources ...
#     deployment.apps "direct" created
#     service "direct" created
```

**What it creates:** a Deployment + Service. No build — the image is used as-is. In 4.18 this is a `Deployment` (not a DeploymentConfig).

```bash
oc status
oc get all -l app=direct
```

**`--image` vs `--docker-image`:** both work; `--image` is the modern spelling. Prefixing with `--image=` (rather than letting new-app guess) avoids new-app misinterpreting the argument as a Git URL or template name.

</details>

---

#### Flavor 2 — Git + Source-to-Image (S2I)

<details>
<summary>💡 Solution</summary>

```bash
oc new-app https://github.com/sclorg/nodejs-ex --name=nodejs-ex
# --> Found image ... (nodejs)
# --> Creating resources ...
#     imagestream "nodejs-ex" created
#     buildconfig "nodejs-ex" created
#     deployment "nodejs-ex" created
#     service "nodejs-ex" created
# --> Building ... (a Build is started automatically)
```

**What it creates:** an ImageStream + **BuildConfig** + Deployment + Service. S2I detects the language (Node.js here), picks a builder image, compiles your source into a runnable image, pushes it to the internal registry, then deploys it.

```bash
# Watch the build
oc get builds
oc logs -f bc/nodejs-ex          # follow the build log
oc get pods -w                   # build pod → then app pod
```

**When S2I triggers:** `oc new-app <git-url>` with no `--image` makes new-app inspect the repo and choose a builder image automatically. This is the "give it source, get a running app" flow.

**Gotcha:** builds need the internal registry and egress to GitHub. If `oc get builds` shows `Error` with a clone failure, your cluster can't reach the Git host — expected on restricted networks.

</details>

---

#### Flavor 3 — From a template

<details>
<summary>💡 Solution</summary>

```bash
# The 'openshift' namespace ships many built-in templates
oc get templates -n openshift | grep -i mysql
# mysql-persistent, mysql-ephemeral, ...

oc new-app --template=mysql-persistent \
  -p MYSQL_USER=app -p MYSQL_PASSWORD=app -p MYSQL_DATABASE=appdb \
  -n lab31
# --> Deploying template "openshift/mysql-persistent" ...
#     secret "mysql" created
#     service "mysql" created
#     persistentvolumeclaim "mysql" created
#     deployment "mysql" created
```

**What it creates:** whatever the template defines — here a Secret, Service, PVC, and Deployment, all parameterized. `-p KEY=value` supplies template parameters.

```bash
oc get all,secret,pvc -l app=mysql-persistent -n lab31
```

**`--template=X` looks in the current namespace first, then `openshift`.** To be explicit: `oc new-app --template=openshift/mysql-persistent`.

</details>

---

#### Flavor 4 — From a Dockerfile in Git (docker strategy)

<details>
<summary>💡 Solution</summary>

```bash
oc new-app https://github.com/sclorg/nodejs-ex --strategy=docker --name=docker-build
# Forces a Docker-strategy build (uses the repo's Dockerfile) instead of S2I
```

**What it creates:** ImageStream + BuildConfig (Docker strategy) + Deployment + Service. Instead of S2I's builder-image assembly, it builds straight from the `Dockerfile` in the repo root.

```bash
oc get bc docker-build -o jsonpath='{.spec.strategy.type}{"\n"}'
# Docker
```

**S2I vs Docker strategy:**

| Strategy | How it builds | When |
|----------|---------------|------|
| `source` (S2I) | Injects your source into a language builder image | Repo has source, no Dockerfile, or you want S2I |
| `docker` | Builds from the repo's Dockerfile | Repo has a Dockerfile you want honored |

`--strategy=docker` overrides new-app's auto-detection.

</details>

---

#### Flavor 5 — ImageStream + code (S2I with an explicit builder)

<details>
<summary>💡 Solution</summary>

```bash
oc new-app --image-stream=openshift/python:3.11-ubi9 \
  --code=https://github.com/sclorg/django-ex \
  --name=django-ex \
  -n lab31
# Uses the specified ImageStream tag as the S2I builder for the given source
```

**What it creates:** BuildConfig (S2I using the *named* builder ImageStreamTag) + ImageStream + Deployment + Service. The difference from Flavor 2 is you're **explicitly choosing** the builder image (`openshift/python:3.11-ubi9`) rather than letting new-app guess.

```bash
oc get bc django-ex -o jsonpath='{.spec.strategy.sourceStrategy.from.name}{"\n"}'
# python:3.11-ubi9
```

**`--code` vs a bare Git URL:** `--code=<url>` explicitly marks the argument as source code, useful when combined with `--image-stream` so new-app doesn't try to auto-detect the language.

---

**After all five — inspect each:**

```bash
for app in direct nodejs-ex mysql docker-build django-ex; do
  echo "=== $app ==="
  oc get all -l app=$app -n lab31 2>/dev/null | head
done

oc status -n lab31          # high-level dependency graph of everything
```

**Cleanup:**

```bash
oc delete project lab31
```

</details>

---

### Lab 3.2 — Author and use a Template (25 min)

Templates parameterize a set of objects so users can stamp out instances with `oc new-app --template`. This lab authors one, installs it cluster-wide, and consumes it as a regular user.

**Prerequisites:**
- Cluster-admin (to install into `openshift`).
- A regular user (e.g. `alice`) and project `oc new-project lab32` for the consume step.

---

#### Step 1 — Save a `hello-template` as YAML

<details>
<summary>💡 Solution</summary>

```bash
cat > hello-template.yaml <<'EOF'
apiVersion: template.openshift.io/v1
kind: Template
metadata:
  name: hello-template
  annotations:
    description: "A parameterized hello-openshift deployment"
    tags: "demo"
parameters:
- name: APP_NAME
  description: Name for the deployment/service
  required: true
- name: REPLICAS
  description: Replica count
  value: "1"
objects:
- apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: ${APP_NAME}
  spec:
    replicas: ${{REPLICAS}}
    selector:
      matchLabels: {app: ${APP_NAME}}
    template:
      metadata:
        labels: {app: ${APP_NAME}}
      spec:
        containers:
        - name: hello
          image: quay.io/openshifttest/hello-openshift:1.2.0
          ports:
          - containerPort: 8080
- apiVersion: v1
  kind: Service
  metadata:
    name: ${APP_NAME}
  spec:
    selector: {app: ${APP_NAME}}
    ports:
    - port: 8080
      targetPort: 8080
EOF
```

**The critical `${{REPLICAS}}` vs `${APP_NAME}` distinction:**

| Syntax | Substitution type | Use for |
|--------|-------------------|---------|
| `${PARAM}` | **String** | Anything that's a string in YAML (names, image tags, labels) |
| `${{PARAM}}` | **Numeric/bool/JSON** | Fields that must be a number or boolean (`replicas`, `port` in some contexts) |

`replicas` must be an integer. `replicas: ${REPLICAS}` would render `replicas: "1"` (a quoted string) and fail schema validation. `replicas: ${{REPLICAS}}` renders `replicas: 1` (a real int). This is the single most common template gotcha.

</details>

---

#### Step 2 — Install the template into `openshift` (cluster-admin)

<details>
<summary>💡 Solution</summary>

```bash
# As cluster-admin. The 'openshift' namespace makes templates visible to ALL users.
oc apply -f hello-template.yaml -n openshift
# template.template.openshift.io/hello-template created

# Verify
oc get template hello-template -n openshift
```

**Why `openshift` namespace:** templates there are globally available — any user can `oc new-app --template=hello-template` from any project. A template in a regular project is only usable within that project. This mirrors how the built-in `mysql-persistent` etc. live in `openshift`.

</details>

---

#### Step 3 — As a regular user, instantiate with parameters

<details>
<summary>💡 Solution</summary>

```bash
oc login -u alice -p <password>
oc project lab32

oc new-app --template=hello-template \
  -p APP_NAME=greeter \
  -p REPLICAS=3
# --> Deploying template "openshift/hello-template" to project lab32
#     deployment "greeter" created
#     service "greeter" created
```

**Alternative — `oc process` then apply** (gives you the rendered YAML to inspect first):

```bash
oc process hello-template -p APP_NAME=greeter -p REPLICAS=3 -n openshift \
  | oc apply -f -

# Or just render to see the substitution:
oc process hello-template -p APP_NAME=greeter -p REPLICAS=3 -n openshift -o yaml \
  | grep -E 'name:|replicas:'
# name: greeter
# replicas: 3        ← an int, thanks to ${{REPLICAS}}
```

`oc new-app --template` and `oc process | oc apply` do the same thing; `oc process` is more transparent because you can view/pipe the output.

</details>

---

#### Step 4 — Verify the resulting Deployment + Service

<details>
<summary>💡 Solution</summary>

```bash
oc get deployment greeter -n lab32
# NAME      READY   UP-TO-DATE   AVAILABLE
# greeter   3/3     3            3          ← 3 replicas = REPLICAS param worked

oc get service greeter -n lab32
# NAME      TYPE        CLUSTER-IP     PORT(S)
# greeter   ClusterIP   172.30.x.x     8080/TCP

# Confirm the numeric replicas rendered correctly (not a string)
oc get deployment greeter -n lab32 -o jsonpath='{.spec.replicas}{"\n"}'
# 3
```

**Verification checklist:**

```bash
oc get template hello-template -n openshift                                  # template installed
oc get deploy,svc -l app=greeter -n lab32                                    # objects created
oc get deploy greeter -n lab32 -o jsonpath='{.spec.replicas}'                # 3 (int)
```

**Cleanup:**

```bash
# As alice
oc delete all -l app=greeter -n lab32
# As cluster-admin
oc delete template hello-template -n openshift
oc delete project lab32
```

</details>

---

### Lab 3.3 — Service & Route end-to-end (20 min)

The Service→Route exposure chain, plus the single most important debugging lesson: what an empty `endpoints` list means and how to fix it.

**Prerequisites:**
- Project: `oc new-project lab33`.

---

#### Step 1 — Deploy `hello-openshift` (3 replicas)

<details>
<summary>💡 Solution</summary>

```bash
oc project lab33
oc create deployment hello \
  --image=quay.io/openshifttest/hello-openshift:1.2.0 \
  --replicas=3
oc rollout status deployment/hello

oc get pods -l app=hello --show-labels
# hello-xxxxx  ... app=hello,pod-template-hash=...
```

Note the pods carry the label `app=hello` — the Service will select on this.

</details>

---

#### Step 2 — Expose port 8080 as a ClusterIP Service named `hello`

<details>
<summary>💡 Solution</summary>

```bash
oc expose deployment hello --port=8080
# service/hello exposed

oc get svc hello
# NAME    TYPE        CLUSTER-IP     PORT(S)
# hello   ClusterIP   172.30.x.x     8080/TCP

# The vital check — endpoints must list the 3 pod IPs
oc get endpoints hello
# NAME    ENDPOINTS
# hello   10.x.x.a:8080,10.x.x.b:8080,10.x.x.c:8080
```

**`oc expose deployment` copies the deployment's selector** (`app=hello`) into the Service, so endpoints populate automatically. Three IPs = three ready pods behind the Service.

</details>

---

#### Step 3 — `curl` the Service from another pod

<details>
<summary>💡 Solution</summary>

```bash
oc run tmp --image=registry.access.redhat.com/ubi9/ubi-minimal:latest \
  -n lab33 -i --rm --restart=Never -- \
  curl -s http://hello:8080
# Hello OpenShift!
```

**Why `http://hello:8080` works from inside the cluster:** the Service name `hello` resolves via cluster DNS to the Service's ClusterIP within the same namespace. The full FQDN is `hello.lab33.svc.cluster.local`, but the short name works from a pod in the same namespace. The Service load-balances across the 3 backend pods.

**`--rm` deletes the tmp pod when curl exits**, so you don't leave debris.

</details>

---

#### Step 4 — Create an HTTP Route and curl it from your workstation

<details>
<summary>💡 Solution</summary>

```bash
oc expose service hello
# route.route.openshift.io/hello exposed

ROUTE=$(oc get route hello -o jsonpath='{.spec.host}')
echo $ROUTE
# hello-lab33.apps.<cluster-domain>

curl -s http://$ROUTE
# Hello OpenShift!
```

The Route makes the Service reachable from **outside** the cluster via the router, using an auto-generated hostname (`<route>-<namespace>.apps.<domain>`).

</details>

---

#### Step 5 — Break the selector; observe empty endpoints; fix

This is the key learning: what happens when a Service's selector no longer matches any pods.

<details>
<summary>💡 Solution</summary>

**Break it** — change the Service selector to something no pod has:

```bash
oc patch service hello --type=merge -p '{"spec":{"selector":{"app":"wrong"}}}'
# service/hello patched

# Endpoints immediately go empty
oc get endpoints hello
# NAME    ENDPOINTS
# hello   <none>            ← the smoking gun

# The Route now returns 503
curl -sI http://$ROUTE | head -1
# HTTP/1.1 503 Service Unavailable

# In-cluster curl also fails now
oc run tmp --image=registry.access.redhat.com/ubi9/ubi-minimal:latest \
  -n lab33 -i --rm --restart=Never -- curl -s -m5 http://hello:8080
# (times out / no response)
```

**Diagnose the pattern:** `oc get endpoints <svc>` showing `<none>` while pods are clearly running means the **Service selector doesn't match the pod labels**. Confirm the mismatch:

```bash
oc get svc hello -o jsonpath='selector={.spec.selector}{"\n"}'
# selector={"app":"wrong"}
oc get pods -l app=hello --show-labels | head -1
# pods have app=hello, not app=wrong
```

**Fix** — restore the correct selector:

```bash
oc patch service hello --type=merge -p '{"spec":{"selector":{"app":"hello"}}}'

# Endpoints repopulate
oc get endpoints hello
# hello   10.x.x.a:8080,10.x.x.b:8080,10.x.x.c:8080

# Route works again
curl -s http://$ROUTE
# Hello OpenShift!
```

**The lesson for the exam:** whenever a Route/Service isn't reachable but pods are Running, `oc get endpoints` is your first move. Populated → problem is the Route or router. `<none>` → the Service selector doesn't match the pods (or the pods aren't Ready). This is the fastest way to bisect the Route→Service→Pod chain.

**Cleanup:**

```bash
oc delete project lab33
```

</details>

---

### Lab 3.4 — Helm install + values (25 min)

Helm packages apps as charts with configurable values, plus release lifecycle (install/upgrade/rollback). This lab exercises the full cycle.

**Prerequisites:**
- `helm` CLI installed (`which helm`; download from https://helm.sh if missing).
- Project: `oc new-project lab34`.
- Egress to the bitnami chart repo (may be blocked on restricted networks — note the ProjectHelmChartRepository alternative in Step 1).

---

#### Step 1 — Add the bitnami repo

<details>
<summary>💡 Solution</summary>

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

helm search repo bitnami/nginx
# NAME            CHART VERSION   APP VERSION   DESCRIPTION
# bitnami/nginx   x.y.z           1.x.x         NGINX Open Source ...
```

**OpenShift-native alternative — `ProjectHelmChartRepository`:** instead of the client-side `helm repo add`, cluster-admins can register a repo so it appears in the OpenShift console's Developer Catalog:

```yaml
apiVersion: helm.openshift.io/v1beta1
kind: ProjectHelmChartRepository
metadata:
  name: bitnami
  namespace: lab34
spec:
  connectionConfig:
    url: https://charts.bitnami.com/bitnami
```

That's the console/GitOps path; the `helm` CLI path in this lab is the exam-typical one.

</details>

---

#### Step 2 — Install `bitnami/nginx` as release `web` with 2 replicas

<details>
<summary>💡 Solution</summary>

```bash
helm install web bitnami/nginx \
  --set service.type=ClusterIP \
  --set replicaCount=2 \
  -n lab34
# NAME: web
# LAST DEPLOYED: ...
# STATUS: deployed
# REVISION: 1

# Verify
helm list -n lab34
# NAME  NAMESPACE  REVISION  STATUS    CHART        APP VERSION
# web   lab34      1         deployed  nginx-x.y.z  1.x.x

oc get deployment,svc -l app.kubernetes.io/instance=web -n lab34
# deployment web-nginx  READY 2/2
# service    web-nginx  ClusterIP
```

**`--set key=value`** overrides individual chart values. For many overrides, use a values file:

```bash
cat > my-values.yaml <<'EOF'
replicaCount: 2
service:
  type: ClusterIP
EOF
helm install web bitnami/nginx -f my-values.yaml -n lab34
```

**Gotcha — bitnami images and PSA:** bitnami charts generally run rootless and work under OpenShift's `restricted-v2` SCC / `restricted` PSA. If a chart's pods fail admission, you'd either set the chart's securityContext values or bind an SCC — but bitnami/nginx should just work.

**Preview what a chart will render before installing:**

```bash
helm template web bitnami/nginx --set replicaCount=2 -n lab34 | less
# renders all manifests without applying — great for inspection
```

</details>

---

#### Step 3 — Create a Route to the Helm-managed Service

<details>
<summary>💡 Solution</summary>

```bash
# Find the service name Helm created
oc get svc -l app.kubernetes.io/instance=web -n lab34
# web-nginx   ClusterIP   ...   80/TCP,443/TCP

oc expose service web-nginx --port=80 -n lab34
# route.route.openshift.io/web-nginx exposed

ROUTE=$(oc get route web-nginx -n lab34 -o jsonpath='{.spec.host}')
curl -sI http://$ROUTE | head -1
# HTTP/1.1 200 OK
```

The Route is a normal OpenShift object pointing at the Helm-created Service — Helm doesn't manage the Route, you add it. (Some charts can create Routes/Ingress themselves via values; here we do it manually.)

</details>

---

#### Step 4 — Upgrade to 3 replicas

<details>
<summary>💡 Solution</summary>

```bash
helm upgrade web bitnami/nginx \
  --reuse-values \
  --set replicaCount=3 \
  -n lab34
# Release "web" has been upgraded. REVISION: 2

# Verify
helm list -n lab34
# web  lab34  2  deployed ...     ← REVISION now 2

oc get deployment web-nginx -n lab34
# READY 3/3
```

**`--reuse-values` is important:** it keeps all the values from the previous release (like `service.type=ClusterIP`) and only changes what you override (`replicaCount`). Without it, `helm upgrade` resets un-specified values to chart defaults — which could revert `service.type` back to `LoadBalancer` and break things.

**Check revision history:**

```bash
helm history web -n lab34
# REVISION  STATUS      CHART        DESCRIPTION
# 1         superseded  nginx-x.y.z  Install complete
# 2         deployed    nginx-x.y.z  Upgrade complete
```

</details>

---

#### Step 5 — Roll back to revision 1

<details>
<summary>💡 Solution</summary>

```bash
helm rollback web 1 -n lab34
# Rollback was a success! Happy Helming!

# Confirm replicas are back to 2 (revision 1's state)
oc get deployment web-nginx -n lab34
# READY 2/2

helm history web -n lab34
# REVISION  STATUS      DESCRIPTION
# 1         superseded  Install complete
# 2         superseded  Upgrade complete
# 3         deployed    Rollback to 1        ← rollback creates a NEW revision
```

**`helm rollback <release> <revision>`** reverts to a prior revision's state — and, like `oc rollout undo`, it records this as a *new* revision (3) rather than deleting history. Revision 3's content equals revision 1's.

**Uninstall the whole release when done:**

```bash
helm uninstall web -n lab34
# release "web" uninstalled

# Note: helm uninstall removes chart-managed objects (Deployment, Service, etc.)
# but NOT the Route you created manually, nor any CRDs the chart installed.
oc delete route web-nginx -n lab34 2>/dev/null
```

**Helm vs oc rollout — parallel concepts:**

| Concept | Helm | oc / Deployment |
|---------|------|-----------------|
| Deploy | `helm install` | `oc apply` / `oc new-app` |
| Change | `helm upgrade` | `oc set` / `oc patch` |
| Undo | `helm rollback N` | `oc rollout undo --to-revision=N` |
| History | `helm history` | `oc rollout history` |

**Cleanup:**

```bash
oc delete project lab34
```

</details>

---

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

1. **`DeploymentConfig` vs `Deployment`** — older repos/docs use DC; in 4.18 use Deployment. Both work but `oc rollout` for DC has slightly different commands (`oc rollout latest dc/<name>` etc.).
2. **`oc expose svc/<x>` creates a route**, but `oc expose deployment/<x>` creates a Service. Be explicit.
3. **Template numeric params** need the `${{PARAM}}` syntax (double-brace) to come through as int/bool — `${PARAM}` always stringifies.
4. **Helm releases are per-namespace**, but CRDs installed by a chart are cluster-scoped — uninstalling the release may leave them around.

---

## 🔗 Docs to bookmark

- Deployments: https://docs.openshift.com/container-platform/4.18/applications/deployments/index.html
- new-app: https://docs.openshift.com/container-platform/4.18/applications/creating_applications.html
- Templates: https://docs.openshift.com/container-platform/4.18/openshift_images/using-templates.html
- Helm: https://docs.openshift.com/container-platform/4.18/applications/working-with-helm-charts.html
- Routes: https://docs.openshift.com/container-platform/4.18/networking/routes/route-configuration.html
