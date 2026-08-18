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
oc get endpoints hello
oc describe svc hello
```

> ❗ **Endpoints empty?** Always means the Service `selector` doesn't match any pod labels. Fix the labels, not the Service.

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
5. From a local `--image-stream=openshift/python:3.11-ubi9 + --code=…`

For each, run `oc status` and `oc get all -l app=<name>`.

### Lab 3.2 - Author and use a Template (25 min)

1. Save the `hello-template` from §2 as a YAML.
2. `oc apply -f hello-template.yaml -n openshift` (note: needs cluster-admin).
3. From a regular user in project `lab32`, `oc new-app --template=hello-template -p APP_NAME=greeter -p REPLICAS=3`.
4. Verify the resulting Deployment + Service.

### Lab 3.3 - Service & Route end-to-end (20 min)

1. Deploy `quay.io/openshifttest/hello-openshift:1.2.0` (3 replicas).
2. Expose port 8080 as a `ClusterIP` Service named `hello`.
3. `curl` it from another pod (`oc run tmp --image=registry.access.redhat.com/ubi9/ubi-minimal -i --rm --restart=Never -- curl -s http://hello:8080`).
4. Create an HTTP Route and `curl` it from your workstation.
5. **Break** the selector mismatch by changing the deployment's labels; observe `oc get endpoints` empty; fix.

### Lab 3.4 - Helm install + values (25 min)

1. Add the bitnami repo.
2. Install `bitnami/nginx` as release `web` in project `lab34` with `service.type=ClusterIP` and 2 replicas (`--set replicaCount=2`).
3. Create a Route to the helm-managed Service.
4. Upgrade to 3 replicas: `helm upgrade web bitnami/nginx --reuse-values --set replicaCount=3`.
5. Roll back: `helm rollback web 1`. Confirm replicas are back to 2.

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

1. **`DeploymentConfig` vs `Deployment`** - older repos/docs use DC; in 4.18 use Deployment. Both work but `oc rollout` for DC has slightly different commands (`oc rollout latest dc/<name>` etc.).
2. **`oc expose svc/<x>` creates a route**, but `oc expose deployment/<x>` creates a Service. Be explicit.
3. **Template numeric params** need the `${{PARAM}}` syntax (double-brace) to come through as int/bool - `${PARAM}` always stringifies.
4. **Helm releases are per-namespace**, but CRDs installed by a chart are cluster-scoped - uninstalling the release may leave them around.

---

## 🔗 Docs to bookmark

- Deployments: `…/applications/deployments/index`
- new-app: `…/applications/creating_applications`
- Templates: `…/openshift_images/using-templates`
- Helm: `…/applications/working-with-helm-charts`
- Routes: `…/networking/routes/route-configuration`
