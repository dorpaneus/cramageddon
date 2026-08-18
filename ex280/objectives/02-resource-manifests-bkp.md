# Objective 2 — Work with Resource Manifests

> **Exam study points:**
> - Deploy applications from YAML resource manifests
> - Update application deployments
> - Deploy applications using Kustomize
> - Work with Kustomize overlays
> - Create and use secrets
> - Create and use configuration maps

`oc` is built on `kubectl`, so everything Kubernetes-native works here. The big OCP-specific things in this objective are Routes, ImageStreams, and the integrated Kustomize support (`oc apply -k`).

---

## §1 — Anatomy of an OpenShift YAML

```yaml
apiVersion: apps/v1           # group/version
kind: Deployment              # resource type
metadata:
  name: hello                 # unique within ns + kind
  namespace: myapp
  labels:
    app: hello
    app.kubernetes.io/name: hello
  annotations:
    description: "EX280 demo"
spec:                         # desired state
  replicas: 3
  selector:
    matchLabels:
      app: hello
  template:
    metadata:
      labels:
        app: hello             # MUST match selector
    spec:
      containers:
        - name: hello
          image: quay.io/openshifttest/hello-openshift:1.2.0
          ports:
            - containerPort: 8080
          resources:
            requests: {cpu: 50m, memory: 64Mi}
            limits:   {cpu: 200m, memory: 128Mi}
```

### Imperative → YAML pattern (use this on the exam!)

```bash
oc create deployment hello --image=quay.io/openshifttest/hello-openshift:1.2.0 \
  --replicas=3 --port=8080 --dry-run=client -o yaml > hello.yaml
# Now edit hello.yaml to add resources, env, etc., then:
oc apply -f hello.yaml
```

### Useful `oc explain` examples

```bash
oc explain deployment
oc explain deployment.spec
oc explain deployment.spec.template.spec.containers
oc explain pod.spec.containers.resources
oc explain --recursive deployment.spec | less
```

## §2 — Updating deployments

```bash
# Image rollout
oc set image deployment/hello hello=quay.io/openshifttest/hello-openshift:1.3.0
oc rollout status deployment/hello
oc rollout history deployment/hello
oc rollout undo deployment/hello                   # rollback
oc rollout undo deployment/hello --to-revision=3

# Environment variables
oc set env deployment/hello LOG_LEVEL=debug
oc set env deployment/hello --list
oc set env deployment/hello LOG_LEVEL-               # unset (note trailing -)

# From a ConfigMap / Secret
oc set env deployment/hello --from=configmap/appconfig
oc set env deployment/hello --from=secret/dbcreds --prefix=DB_

# Replicas
oc scale deployment/hello --replicas=5

# Resources
oc set resources deployment/hello --limits=cpu=500m,memory=256Mi --requests=cpu=100m,memory=64Mi

# Pause / resume rollouts (batch multiple changes)
oc rollout pause deployment/hello
# … several `oc set` commands …
oc rollout resume deployment/hello
```

### `oc set volume`

```bash
# Mount a secret as a file
oc set volume deployment/hello --add --type=secret --secret-name=tls \
  --mount-path=/etc/tls --name=tls-vol

# Mount a PVC
oc set volume deployment/hello --add --type=pvc --claim-name=data \
  --claim-size=2Gi --mount-path=/var/lib/data --name=data

# Remove the volume
oc set volume deployment/hello --remove --name=tls-vol
```

## §3 — ConfigMaps

Plain key/value (or whole files) consumed by pods as env vars or files.

```bash
# Create from literals
oc create configmap appconfig \
  --from-literal=LOG_LEVEL=info \
  --from-literal=MAX_CONN=20

# Create from a file (key = filename, value = file contents)
oc create configmap nginx-conf --from-file=nginx.conf

# Create from a directory (every file becomes a key)
oc create configmap site --from-file=./site/

# Inspect
oc get cm appconfig -o yaml
oc describe cm appconfig
```

### YAML form

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: appconfig
data:
  LOG_LEVEL: info
  MAX_CONN: "20"
  app.properties: |
    server.port=8080
    server.host=0.0.0.0
```

### Consuming a ConfigMap

```yaml
# As env vars (all keys)
spec:
  containers:
    - name: app
      envFrom:
        - configMapRef:
            name: appconfig
```

```yaml
# As individual env vars
env:
  - name: LOG_LEVEL
    valueFrom:
      configMapKeyRef:
        name: appconfig
        key: LOG_LEVEL
```

```yaml
# As mounted files
volumes:
  - name: cfg
    configMap:
      name: appconfig
volumeMounts:
  - name: cfg
    mountPath: /etc/app
```

## §4 — Secrets

Same shape as ConfigMaps but **base64-encoded** and treated differently by RBAC/audit.

```bash
# Generic
oc create secret generic dbcreds \
  --from-literal=username=app \
  --from-literal=password='hunter2'

# TLS (for routes / ingress)
oc create secret tls mytls --cert=server.crt --key=server.key

# Docker pull secret (for private registries)
oc create secret docker-registry myreg \
  --docker-server=quay.io \
  --docker-username=alice --docker-password=xxx --docker-email=a@b.c
oc secrets link default myreg --for=pull          # SA "default" can use it for image pulls
oc secrets link builder myreg                     # also for builds

# Inspect — values are base64
oc get secret dbcreds -o yaml
oc get secret dbcreds -o jsonpath='{.data.password}' | base64 -d ; echo
```

### Built-in secret types

| Type | Used for |
|------|----------|
| `Opaque` (default for `generic`) | Arbitrary key/value |
| `kubernetes.io/tls` | TLS cert + key |
| `kubernetes.io/dockerconfigjson` | Image pull |
| `kubernetes.io/basic-auth` | username/password pair |
| `kubernetes.io/ssh-auth` | SSH private key |
| `kubernetes.io/service-account-token` | (auto-managed) |

### Consuming a Secret

```yaml
# As env var
env:
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: dbcreds
        key: password

# As a file
volumes:
  - name: creds
    secret:
      secretName: dbcreds
      defaultMode: 0400        # restrict perms
volumeMounts:
  - name: creds
    mountPath: /etc/creds
    readOnly: true
```

> 🛡️ **Pod Security Admission (PSA) note:** at 4.18, the `restricted` PSA profile rejects pods that don't drop ALL capabilities and set `runAsNonRoot: true`. If a CM/Secret mount triggers a security error, it's almost always PSA — not the volume itself. See `09-application-security.md`.

## §5 — Kustomize basics

`oc` ships Kustomize. The trigger is a `kustomization.yaml` file.

### A minimal base

```
myapp/
├── base/
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   └── configmap.yaml
└── overlays/
    ├── dev/
    │   ├── kustomization.yaml
    │   └── replicas-patch.yaml
    └── prod/
        ├── kustomization.yaml
        ├── replicas-patch.yaml
        └── resources-patch.yaml
```

`base/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
  - configmap.yaml
commonLabels:
  app: myapp
namespace: myapp
```

### Apply / preview

```bash
# Preview the rendered YAML
oc kustomize base/
oc kustomize overlays/prod/

# Apply
oc apply -k base/
oc apply -k overlays/prod/

# Delete what was applied
oc delete -k overlays/prod/
```

## §6 — Kustomize overlays

`overlays/prod/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base                     # inherit
namespace: myapp-prod
nameSuffix: -prod
commonLabels:
  env: prod
patches:
  - path: replicas-patch.yaml
    target:
      kind: Deployment
      name: hello
images:
  - name: quay.io/openshifttest/hello-openshift
    newTag: 1.3.0
configMapGenerator:
  - name: appconfig
    behavior: merge
    literals:
      - LOG_LEVEL=warn
```

`overlays/prod/replicas-patch.yaml` (strategic merge):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello
spec:
  replicas: 5
```

> Common kustomize transformers you'll be asked about: `namespace:`, `namePrefix/Suffix`, `commonLabels`, `commonAnnotations`, `images:`, `replicas:`, `configMapGenerator`, `secretGenerator`, `patches:` (strategic merge or JSON6902).

---

## 🧪 Labs

### Lab 2.1 — From scratch to running (20 min)

The full imperative→declarative→exposed pipeline for a single app. Every command here is one you'll repeat on the exam.

**Prerequisites:**
- Project: `oc new-project lab21`.

---

#### Step 1 — Generate a Deployment manifest (3 replicas, port 8080)

<details>
<summary>💡 Solution</summary>

```bash
oc project lab21

oc create deployment hello \
  --image=quay.io/openshifttest/hello-openshift:1.2.0 \
  --replicas=3 \
  --port=8080 \
  --dry-run=client -o yaml > hello-deploy.yaml

cat hello-deploy.yaml
```

You get a full Deployment. The `--port=8080` populates `containerPort`:

```yaml
      containers:
      - image: quay.io/openshifttest/hello-openshift:1.2.0
        name: hello-openshift
        ports:
        - containerPort: 8080
        resources: {}
```

**Why `--dry-run=client -o yaml` first (rather than just creating it):** it gives you an editable manifest so you can add resources, probes, env, etc. before anything hits the cluster. This "generate then edit then apply" loop is the fastest reliable way to build correct YAML under exam time pressure.

</details>

---

#### Step 2 — Add resource requests/limits

<details>
<summary>💡 Solution</summary>

Edit `hello-deploy.yaml`, replace `resources: {}` with:

```yaml
        resources:
          requests:
            cpu: 100m
            memory: 64Mi
          limits:
            cpu: 250m
            memory: 128Mi
```

**Validate before applying:**

```bash
oc apply -f hello-deploy.yaml --dry-run=server
# deployment.apps/hello created (server dry run)   ← passes admission, nothing persisted
```

`--dry-run=server` sends it to the API server for full validation (including admission controllers) without persisting — catches YAML/schema errors before you commit.

</details>

---

#### Step 3 — Apply and verify pods running

<details>
<summary>💡 Solution</summary>

```bash
oc apply -f hello-deploy.yaml
# deployment.apps/hello created

oc rollout status deployment/hello
# deployment "hello" successfully rolled out

oc get pods -l app=hello
# hello-xxxxx-aaaaa   1/1   Running
# hello-xxxxx-bbbbb   1/1   Running
# hello-xxxxx-ccccc   1/1   Running
```

Three Running pods = success. If any are `Pending`, `oc describe pod <name>` and read the Events (likely a resource or PSA issue).

</details>

---

#### Step 4 — Add a Service (port 8080 → targetPort 8080)

<details>
<summary>💡 Solution</summary>

**Imperative (simplest):**

```bash
oc expose deployment hello --port=8080 --target-port=8080
# service/hello exposed

oc get svc hello
# NAME    TYPE        CLUSTER-IP     PORT(S)
# hello   ClusterIP   172.30.x.x     8080/TCP
```

**Declarative alternative** (generate + apply, to match the lab's YAML theme):

```bash
oc create service clusterip hello --tcp=8080:8080 --dry-run=client -o yaml > hello-svc.yaml
oc apply -f hello-svc.yaml
```

**Confirm the Service found the pods:**

```bash
oc get endpoints hello
# hello   10.x.x.x:8080,10.x.x.x:8080,10.x.x.x:8080    ← 3 pod IPs = wired correctly
```

Empty endpoints = the Service selector doesn't match the pod labels. `oc expose deployment` copies the deployment's selector automatically, so this normally just works.

</details>

---

#### Step 5 — Expose via Route and `curl` it

<details>
<summary>💡 Solution</summary>

```bash
oc expose service hello
# route.route.openshift.io/hello exposed

ROUTE=$(oc get route hello -o jsonpath='{.spec.host}')
echo $ROUTE
# hello-lab21.apps.<cluster-domain>

curl -s http://$ROUTE
# Hello OpenShift!
```

**The exposure chain, end to end:**

```
Deployment (pods) → Service (ClusterIP, stable virtual IP) → Route (external hostname via router)
```

- `oc expose deployment` → creates the **Service**.
- `oc expose service` → creates the **Route**.

Two different `oc expose` calls on two different object kinds. A common mistake is trying `oc expose deployment --type=route` (there's no such thing) — Routes come from exposing a Service.

**Verification checklist:**

```bash
oc get deploy,svc,route,endpoints -n lab21
curl -s http://$(oc get route hello -o jsonpath='{.spec.host}')   # Hello OpenShift!
```

Keep `lab21` for Lab 2.2. Otherwise `oc delete project lab21`.

</details>

---

### Lab 2.2 — Patch storm (15 min)

The everyday mutation commands: `set image`, `rollout undo`, `patch`, `label`. Fast, imperative changes to a live Deployment — exactly what the exam rewards.

**Prerequisites:**
- The `hello` Deployment in `lab21` from Lab 2.1.

---

#### Step 1 — Update the image to a bad tag; watch the rollout fail

<details>
<summary>💡 Solution</summary>

```bash
oc set image deployment/hello hello-openshift=quay.io/openshifttest/hello-openshift:does-not-exist -n lab21
# deployment.apps/hello image updated

oc rollout status deployment/hello -n lab21 --timeout=60s
# Waiting for deployment "hello" rollout to finish: 1 out of 3 new replicas have been updated...
# error: deployment "hello" exceeded its progress deadline   ← (or it just hangs)

oc get pods -l app=hello -n lab21
# hello-OLD-xxxxx   1/1   Running            (old replicas kept alive)
# hello-NEW-yyyyy   0/1   ImagePullBackOff   (new one can't pull)
```

**The container name matters:** `oc set image deployment/hello <container>=<image>`. The container is named `hello-openshift` (from the original image). Confirm with:

```bash
oc get deploy hello -n lab21 -o jsonpath='{.spec.template.spec.containers[0].name}{"\n"}'
# hello-openshift
```

**Why the app stays up:** a Deployment's `RollingUpdate` strategy keeps old pods running until new ones become Ready. Since the new image never pulls, the old pods are never torn down — no outage. This is the safety net rolling updates provide.

</details>

---

#### Step 2 — `oc rollout undo` and confirm the old image is back

<details>
<summary>💡 Solution</summary>

```bash
oc rollout undo deployment/hello -n lab21
# deployment.apps/hello rolled back

oc rollout status deployment/hello -n lab21
# deployment "hello" successfully rolled out

# Confirm the good image is restored
oc get deploy hello -n lab21 -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
# quay.io/openshifttest/hello-openshift:1.2.0
```

**Rollout history commands:**

```bash
oc rollout history deployment/hello -n lab21
# REVISION  CHANGE-CAUSE
# 1         <none>
# 2         <none>   (the bad-image revision)
# 3         <none>   (the undo = a new revision reverting to rev 1's spec)

# Roll back to a SPECIFIC revision, not just the previous one:
oc rollout undo deployment/hello --to-revision=1 -n lab21
```

`oc rollout undo` reverts to the previous revision by default; `--to-revision=N` targets a specific one from the history.

</details>

---

#### Step 3 — Change replicas to 5 with `oc patch`

<details>
<summary>💡 Solution</summary>

```bash
oc patch deployment hello -n lab21 --type=merge -p '{"spec":{"replicas":5}}'
# deployment.apps/hello patched

oc get deployment hello -n lab21
# NAME    READY   UP-TO-DATE   AVAILABLE
# hello   5/5     5            5
```

**Three ways to scale (know all three for the exam):**

```bash
oc patch deployment hello -n lab21 --type=merge -p '{"spec":{"replicas":5}}'   # patch
oc scale deployment/hello --replicas=5 -n lab21                                 # scale (cleanest)
oc edit deployment hello -n lab21                                               # edit interactively
```

`oc scale` is the purpose-built command; `oc patch` is more general (any field, scriptable).

</details>

---

#### Step 4 — Add a label `tier=frontend` to the Deployment

<details>
<summary>💡 Solution</summary>

```bash
oc label deployment hello tier=frontend -n lab21
# deployment.apps/hello labeled

# Verify
oc get deployment hello -n lab21 --show-labels
# NAME    ...  LABELS
# hello   ...  app=hello,tier=frontend
```

**Gotcha — labeling the Deployment object ≠ labeling the pods.** `oc label deployment` adds the label to the Deployment's own metadata, NOT to the pods it creates. To label the pods, you'd edit `spec.template.metadata.labels` (which triggers a rollout). To confirm:

```bash
oc get pods -l app=hello -n lab21 --show-labels
# pods still show only app=hello,pod-template-hash=...  (no tier=frontend)
```

**Overwrite an existing label** needs `--overwrite`:

```bash
oc label deployment hello tier=backend --overwrite -n lab21
```

**Remove a label** with a trailing minus:

```bash
oc label deployment hello tier- -n lab21
```

**Cleanup:**

```bash
oc delete project lab21
```

</details>

---

### Lab 2.3 — ConfigMap + Secret end-to-end (25 min)

Injecting configuration and credentials into a pod is bread-and-butter EX280 work. This lab shows both the "one key at a time" and "prefix the whole thing" injection styles.

**Prerequisites:**
- Project: `oc new-project lab23`.

---

#### Step 1 — Create ConfigMap `appconfig`

<details>
<summary>💡 Solution</summary>

```bash
oc create configmap appconfig \
  --from-literal=LOG_LEVEL=debug \
  --from-literal=GREETING=Hello \
  -n lab23

# Verify
oc get configmap appconfig -n lab23 -o yaml
# data:
#   GREETING: Hello
#   LOG_LEVEL: debug
```

**Creation variants:**

```bash
# From a file (key = filename)
oc create configmap appconfig --from-file=app.properties

# From an env-style file (each KEY=VAL line becomes a key)
oc create configmap appconfig --from-env-file=config.env

# From a whole directory
oc create configmap appconfig --from-file=./configdir/
```

</details>

---

#### Step 2 — Create Secret `dbcreds`

<details>
<summary>💡 Solution</summary>

```bash
oc create secret generic dbcreds \
  --from-literal=username=app \
  --from-literal=password=hunter2 \
  -n lab23

# Verify (values are base64-encoded at rest)
oc get secret dbcreds -n lab23 -o jsonpath='{.data.username}' | base64 -d; echo
# app
oc get secret dbcreds -n lab23 -o jsonpath='{.data.password}' | base64 -d; echo
# hunter2
```

**Secrets are base64, not encrypted** — base64 is just encoding, trivially reversible. Anyone with read access to the Secret can decode it. Secrets differ from ConfigMaps mainly in intent, RBAC defaults (the `view` role can't read Secrets), and the fact that they can be encrypted at rest at the etcd level if the cluster is configured for it.

</details>

---

#### Step 3 — Deploy hello-openshift and inject both via `oc set env`

The requirement: `LOG_LEVEL` and `GREETING` come from the ConfigMap (same names), and `DB_USERNAME`/`DB_PASSWORD` come from the Secret (note the `DB_` prefix on the Secret keys `username`/`password`).

<details>
<summary>💡 Solution</summary>

```bash
# Deploy first
oc create deployment hello \
  --image=quay.io/openshifttest/hello-openshift:1.2.0 -n lab23
oc rollout status deployment/hello -n lab23

# Inject ALL ConfigMap keys as-is (LOG_LEVEL, GREETING)
oc set env deployment/hello --from=configmap/appconfig -n lab23
# deployment.apps/hello updated

# Inject ALL Secret keys WITH a DB_ prefix (username→DB_USERNAME, password→DB_PASSWORD)
oc set env deployment/hello --from=secret/dbcreds --prefix=DB_ -n lab23
# deployment.apps/hello updated
```

**The `--prefix` flag** is exactly built for this: it prepends `DB_` to every key pulled from the source. So Secret key `username` becomes env var `DB_USERNAME`, `password` becomes `DB_PASSWORD`.

**Inspect the resulting env config on the Deployment:**

```bash
oc set env deployment/hello --list -n lab23
# # deployment/hello, container hello-openshift
# LOG_LEVEL from configmap appconfig, key LOG_LEVEL
# GREETING from configmap appconfig, key GREETING
# DB_USERNAME from secret dbcreds, key username
# DB_PASSWORD from secret dbcreds, key password
```

Note these render as `valueFrom.configMapKeyRef` / `secretKeyRef` in the pod spec — the values are *referenced*, not copied. Update the ConfigMap/Secret and restart the pod to pick up changes.

**Single-key injection** (if you only wanted one key, not the whole source):

```bash
oc set env deployment/hello --from=configmap/appconfig --keys=LOG_LEVEL -n lab23
```

**Declarative equivalent** (`envFrom` for whole-source, without per-key prefix control on secretRef — prefix works here too):

```yaml
        envFrom:
        - configMapRef:
            name: appconfig
        - secretRef:
            name: dbcreds
          prefix: DB_
```

</details>

---

#### Step 4 — `oc rsh` into the pod and verify the env vars

<details>
<summary>💡 Solution</summary>

```bash
oc rsh -n lab23 deploy/hello
# now inside the pod:
$ env | grep -E 'LOG_|GREETING|DB_'
# LOG_LEVEL=debug
# GREETING=Hello
# DB_USERNAME=app
# DB_PASSWORD=hunter2
$ exit
```

**One-liner without an interactive shell:**

```bash
oc exec -n lab23 deploy/hello -- env | grep -E 'LOG_|GREETING|DB_'
# LOG_LEVEL=debug
# GREETING=Hello
# DB_USERNAME=app
# DB_PASSWORD=hunter2
```

All four present with the right names ⇒ success.

**`oc rsh` vs `oc exec`:**
- `oc rsh <pod>` opens an interactive shell (like SSH into the container).
- `oc exec <pod> -- <cmd>` runs a single command and returns.
- Both accept `deploy/hello` (targets one of the deployment's pods) or an explicit pod name.

**Cleanup:**

```bash
oc delete project lab23
```

</details>

---

### Lab 2.4 — Kustomize base + 2 overlays (40 min)

Kustomize lets you keep one base set of manifests and layer environment-specific patches on top — no templating language. `oc apply -k` has it built in.

**Prerequisites:**
- `oc` (Kustomize is bundled; no separate install needed).
- A scratch directory: `mkdir -p ~/lab24 && cd ~/lab24`.

---

#### Step 1 — Build the directory layout

<details>
<summary>💡 Solution</summary>

```bash
cd ~/lab24
mkdir -p base overlays/dev overlays/prod
```

Target structure:

```
lab24/
├── base/
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   └── configmap.yaml
└── overlays/
    ├── dev/
    │   └── kustomization.yaml
    └── prod/
        ├── kustomization.yaml
        └── configmap-patch.yaml
```

**The mental model:** `base/` holds environment-agnostic manifests. Each overlay has its own `kustomization.yaml` that references the base and applies patches/additions. You `oc apply -k overlays/dev` to render base+dev and apply the result.

</details>

---

#### Step 2 — Populate `base/` (Deployment, Service, ConfigMap + kustomization)

<details>
<summary>💡 Solution</summary>

```bash
# base/deployment.yaml
cat > base/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello
spec:
  replicas: 1
  selector: {matchLabels: {app: hello}}
  template:
    metadata: {labels: {app: hello}}
    spec:
      containers:
      - name: hello
        image: quay.io/openshifttest/hello-openshift:1.2.0
        ports:
        - containerPort: 8080
        envFrom:
        - configMapRef:
            name: hello-config
EOF

# base/service.yaml
cat > base/service.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: hello
spec:
  selector: {app: hello}
  ports:
  - port: 8080
    targetPort: 8080
EOF

# base/configmap.yaml
cat > base/configmap.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: hello-config
data:
  LOG_LEVEL: info
EOF

# base/kustomization.yaml — ties the three together
cat > base/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- deployment.yaml
- service.yaml
- configmap.yaml
EOF
```

**Test the base renders on its own:**

```bash
oc kustomize base
# prints the combined YAML (Deployment + Service + ConfigMap) — no patches yet
```

</details>

---

#### Step 3 — `dev` overlay: replicas=1, label `env: dev`

<details>
<summary>💡 Solution</summary>

```bash
cat > overlays/dev/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: hello-dev
resources:
- ../../base
commonLabels:
  env: dev
replicas:
- name: hello
  count: 1
EOF
```

**What each field does:**
- `resources: [../../base]` — pull in everything the base defines.
- `namespace: hello-dev` — stamp every rendered object into that namespace.
- `commonLabels: {env: dev}` — add `env: dev` to all objects AND their selectors.
- `replicas: [{name: hello, count: 1}]` — override the Deployment's replica count without editing the base.

**Render to check:**

```bash
oc kustomize overlays/dev | grep -E 'namespace:|replicas:|env:'
```

</details>

---

#### Step 4 — `prod` overlay: replicas=5, label `env: prod`, image `1.3.0`, `LOG_LEVEL=warn`, namespace `hello-prod`

<details>
<summary>💡 Solution</summary>

```bash
# A patch to merge LOG_LEVEL=warn into the ConfigMap
cat > overlays/prod/configmap-patch.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: hello-config
data:
  LOG_LEVEL: warn
EOF

cat > overlays/prod/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: hello-prod
resources:
- ../../base
commonLabels:
  env: prod
replicas:
- name: hello
  count: 5
images:
- name: quay.io/openshifttest/hello-openshift
  newTag: "1.3.0"
patches:
- path: configmap-patch.yaml
  target:
    kind: ConfigMap
    name: hello-config
EOF
```

**The `images:` transformer** swaps the tag cluster-wide in the rendered output without touching the base Deployment — `newTag: "1.3.0"` changes `:1.2.0` → `:1.3.0`. You can also set `newName` to change the whole image repository.

**The `patches:` block** applies a strategic-merge patch: the `configmap-patch.yaml` overrides just the `LOG_LEVEL` key, leaving other ConfigMap data intact.

**Render to verify all four changes landed:**

```bash
oc kustomize overlays/prod | grep -E 'namespace:|image:|replicas:|LOG_LEVEL:|env:'
# namespace: hello-prod
# image: quay.io/openshifttest/hello-openshift:1.3.0
# replicas: 5
# LOG_LEVEL: warn
# env: prod  (on labels)
```

</details>

---

#### Step 5 — Apply both; confirm the differences

<details>
<summary>💡 Solution</summary>

```bash
# Namespaces must exist first (kustomize sets the namespace field but doesn't create the ns)
oc create namespace hello-dev
oc create namespace hello-prod

# Apply each overlay
oc apply -k overlays/dev
oc apply -k overlays/prod

# Compare
oc get deploy,svc,cm,po -n hello-dev
# hello  READY 1/1 ... image :1.2.0, LOG_LEVEL=info

oc get deploy,svc,cm,po -n hello-prod
# hello  READY 5/5 ... image :1.3.0, LOG_LEVEL=warn

# Spot-check the distinguishing fields
oc get deploy hello -n hello-dev  -o jsonpath='dev:  {.spec.replicas} {.spec.template.spec.containers[0].image}{"\n"}'
oc get deploy hello -n hello-prod -o jsonpath='prod: {.spec.replicas} {.spec.template.spec.containers[0].image}{"\n"}'
# dev:  1 quay.io/openshifttest/hello-openshift:1.2.0
# prod: 5 quay.io/openshifttest/hello-openshift:1.3.0

oc get cm hello-config -n hello-dev  -o jsonpath='{.data.LOG_LEVEL}{"\n"}'   # info
oc get cm hello-config -n hello-prod -o jsonpath='{.data.LOG_LEVEL}{"\n"}'   # warn
```

Same base, two environments, differing only by the overlay patches — that's the whole value of Kustomize.

</details>

---

#### Step 6 — Delete both with `oc delete -k`

<details>
<summary>💡 Solution</summary>

```bash
oc delete -k overlays/dev
oc delete -k overlays/prod

# The namespaces were created manually, so remove them too:
oc delete namespace hello-dev hello-prod
```

**`oc delete -k <overlay>`** renders the same set of objects and deletes them — the reverse of `apply -k`. Handy for clean teardown of everything an overlay created.

**Exam relevance:** Kustomize appears when a task says "deploy this app to dev and prod with different replica counts / image tags / config." Knowing `oc apply -k` and the four common transformers (`namespace`, `commonLabels`, `replicas`, `images`) plus `patches` covers essentially all of it. You do NOT need a separate `kustomize` binary — it's built into `oc`/`kubectl`.

</details>

---

---

## ⚡ Drills (timed, no docs)

| Drill | Target time |
|-------|-------------|
| Generate a Deployment YAML for any image with 2 containers | 90 s |
| Create a Secret of type `tls` from cert.pem / key.pem | 30 s |
| Patch a deployment to add a `nodeSelector: disktype=ssd` | 60 s |
| `oc kustomize` an overlay & pipe to `oc apply -f -` | 30 s |
| Add a ConfigMap-backed volume to a deployment via `oc set volume` | 60 s |
| Look up the YAML path for `livenessProbe.httpGet.path` with `oc explain` | 30 s |

---

## 🔗 Docs to bookmark

- Working with manifests: https://docs.openshift.com/container-platform/4.18/building_applications/working-with-projects.html
- ConfigMaps & Secrets: https://docs.openshift.com/container-platform/4.18/nodes/pods/nodes-pods-configmaps.html and https://docs.openshift.com/container-platform/4.18/nodes/pods/nodes-pods-secrets.html
- Kustomize in `oc`: https://docs.openshift.com/container-platform/4.18/cli_tools/openshift-cli-oc/managing-cli-plug-ins.html (and the upstream <https://kustomize.io>)
