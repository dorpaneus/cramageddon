<div align="center">

[⬅️ Prev: Manage OpenShift Container Platform](./01-manage-ocp.md) &nbsp;·&nbsp; [🏠 Home](../README.md) &nbsp;·&nbsp; [Next: Deploy applications ➡️](./03-deploy-applications.md)

</div>

# Objective 2 - Work with Resource Manifests

> **Exam study points:**
> - Deploy applications from YAML resource manifests
> - Update application deployments
> - Deploy applications using Kustomize
> - Work with Kustomize overlays
> - Create and use secrets
> - Create and use configuration maps

`oc` is built on `kubectl`, so everything Kubernetes-native works here. The big OCP-specific things in this objective are Routes, ImageStreams, and the integrated Kustomize support (`oc apply -k`).

## §1 - Anatomy of an OpenShift YAML

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

> 🛡️ **Security note:** ConfigMap and Secret volumes are allowed by every SCC, including the default `restricted-v2`. If a pod with such a mount fails, look elsewhere: a wrong key name, a missing object (`CreateContainerConfigError`), or an image that can't run as a random non-root UID. "would violate PodSecurity" lines are usually warnings, not the cause. See `09-application-security.md`.

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
labels:
  - pairs:
      app: myapp
    includeTemplates: true     # also label the pod templates (selectors are left alone)
namespace: myapp
```

> `commonLabels:` still works but is **deprecated** in Kustomize v5 (which `oc` bundles). It also rewrites selectors, which are immutable on an existing Deployment — so adding a common label later breaks `oc apply`. Prefer `labels:`.

> `namespace:` sets the namespace on every resource but does **not** create it. Create the namespace first (`oc new-project` / `oc create namespace`) or include a `Namespace` manifest in `resources:`.

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
labels:
  - pairs:
      env: prod
    includeTemplates: true
patches:
  - path: replicas-patch.yaml
    target:
      kind: Deployment
      name: hello                  # the base name — patches match before nameSuffix is applied
images:
  - name: quay.io/openshifttest/hello-openshift
    newTag: "1.2.0"                # change the tag…
    # digest: sha256:…             # …or pin an immutable digest instead (overrides the tag)
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

`configMapGenerator` with `behavior: merge` overlays new keys onto a ConfigMap of the same name from the base. If the base ConfigMap was itself **generated** (`configMapGenerator`), the result gets a content-hash suffix (`appconfig-m87d62t9k4`) and Kustomize rewrites every reference to it — so changing a value triggers a new rollout automatically. If the base lists it as a plain `configmap.yaml`, the name stays `appconfig` and pods only see the new value after `oc rollout restart`.

> Common kustomize transformers you'll be asked about: `namespace:`, `namePrefix/Suffix`, `labels` (formerly `commonLabels`), `commonAnnotations`, `images:`, `replicas:`, `configMapGenerator`, `secretGenerator`, `patches:` (strategic merge or JSON6902).

---

## 🧪 Labs

> ℹ️ **About the `hello-openshift` image:** it's a single static binary with **no shell**, so `oc rsh` / `oc exec … env` won't work in its pods. To look inside, use `oc debug` with a different image — it copies the pod spec (including env vars and mounts) but swaps the image: `oc debug deployment/hello --image=registry.access.redhat.com/ubi9/ubi-minimal -- env`.

### Lab 2.1 — From scratch to running (20 min)

1. Generate a Deployment manifest for `quay.io/openshifttest/hello-openshift:1.2.0`, 3 replicas, port 8080, into project `lab21`.
2. Add resource requests/limits.
3. Apply, verify pods running.
4. Add a Service (port 8080 → targetPort 8080) and apply.
5. Expose via Route, `curl` it.

<details>
<summary>💡 Solution Step 1</summary>

```bash
oc new-project lab21

oc create deployment hello \
  --image=quay.io/openshifttest/hello-openshift:1.2.0 \
  --replicas=3 --port=8080 \
  --dry-run=client -o yaml > hello.yaml
```

`oc create deployment` names the container after the image (`hello-openshift`) and labels everything `app=hello`. Check with `grep -n 'name:\|app:' hello.yaml`.

</details>

<details>
<summary>💡 Solution Step 2</summary>

**Option A — edit the file.** Replace `resources: {}` under the container with:

```yaml
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
```

**Option B — let `oc` edit the file for you** (no cluster contact, no indentation mistakes):

```bash
oc set resources -f hello.yaml --local \
  --requests=cpu=50m,memory=64Mi --limits=cpu=200m,memory=128Mi \
  -o yaml > hello-res.yaml && mv hello-res.yaml hello.yaml
```

`--local` makes most `oc set …` commands work on a file instead of the live object — handy for building manifests.

</details>

<details>
<summary>💡 Solution Step 3</summary>

```bash
oc apply -f hello.yaml
oc rollout status deployment/hello
oc get pods -l app=hello
# hello-xxxxx-aaaaa   1/1   Running   0   20s
# hello-xxxxx-bbbbb   1/1   Running   0   20s
# hello-xxxxx-ccccc   1/1   Running   0   20s

# Confirm the resources landed:
oc get deployment hello -o jsonpath='{.spec.template.spec.containers[0].resources}{"\n"}'
```

</details>

<details>
<summary>💡 Solution Step 4</summary>

Generate the Service as YAML too, so it lives next to the Deployment:

```bash
oc create service clusterip hello --tcp=8080:8080 --dry-run=client -o yaml > svc.yaml
oc apply -f svc.yaml
```

`oc create service clusterip hello` sets the selector to `app=hello` — which matches the pods from Step 3. (Alternative: `oc expose deployment hello --port=8080`, which copies the Deployment's selector.)

Verify the Service found the pods:

```bash
oc get svc hello
oc get endpointslices -l kubernetes.io/service-name=hello
# hello-xxxxx   IPv4   8080   10.x.x.x,10.x.x.x,10.x.x.x   ← 3 addresses
```

</details>

<details>
<summary>💡 Solution Step 5</summary>

```bash
oc expose service hello
# route.route.openshift.io/hello exposed

HOST=$(oc get route hello -o jsonpath='{.spec.host}')
curl -s http://$HOST
# Hello OpenShift!
```

**Keep it declarative:** `oc get route hello -o yaml > route.yaml` gives you the third manifest; from then on `oc apply -f hello.yaml -f svc.yaml -f route.yaml` recreates the whole app.

Keep `lab21` for Lab 2.2.

</details>

### Lab 2.2 — Patch storm (15 min)

In `lab21`:

1. Update the image to a non-existing tag via `oc set image`, watch the rollout fail.
2. `oc rollout undo` and confirm the old image is back.
3. Change replicas to 5 with `oc patch`.
4. Add a label `tier=frontend` to the deployment with `oc label`.

<details>
<summary>💡 Solution Step 1</summary>

```bash
oc set image deployment/hello hello-openshift=quay.io/openshifttest/hello-openshift:does-not-exist
# deployment.apps/hello image updated

oc rollout status deployment/hello --timeout=60s
# Waiting for deployment "hello" rollout to finish: 1 out of 3 new replicas have been updated...
# error: timed out waiting for the condition

oc get pods -l app=hello
# hello-new-xxxxx   0/1   ImagePullBackOff   0   50s   ← new ReplicaSet
# hello-old-aaaaa   1/1   Running            0   10m   ← old pods keep serving
# hello-old-bbbbb   1/1   Running            0   10m
# hello-old-ccccc   1/1   Running            0   10m
```

The rolling update protects you: the old pods keep serving because the new ones never become Ready. `curl http://$HOST` still works.

The container name (`hello-openshift`) is required in `oc set image`; find it with `oc get deployment hello -o jsonpath='{.spec.template.spec.containers[*].name}'`.

</details>

<details>
<summary>💡 Solution Step 2</summary>

```bash
oc rollout history deployment/hello
# REVISION  CHANGE-CAUSE
# 1         <none>
# 2         <none>

oc rollout undo deployment/hello
# deployment.apps/hello rolled back

oc rollout status deployment/hello
oc get deployment hello -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
# quay.io/openshifttest/hello-openshift:1.2.0
```

To make the history readable, annotate each change:

```bash
oc annotate deployment/hello kubernetes.io/change-cause="rollback to 1.2.0" --overwrite
oc rollout history deployment/hello
```

</details>

<details>
<summary>💡 Solution Step 3</summary>

```bash
oc patch deployment hello -p '{"spec":{"replicas":5}}'
oc get deployment hello
# NAME    READY   UP-TO-DATE   AVAILABLE
# hello   5/5     5            5
```

(`oc scale deployment/hello --replicas=5` is the purpose-built alternative.)

</details>

<details>
<summary>💡 Solution Step 4</summary>

```bash
oc label deployment hello tier=frontend
oc get deployment hello --show-labels
# ... app=hello,tier=frontend
```

**Gotcha — this labels the Deployment object only, not its pods.** `oc get pods -l tier=frontend` returns nothing. To label the pods, change the pod template (which triggers a rollout):

```bash
oc patch deployment hello -p '{"spec":{"template":{"metadata":{"labels":{"tier":"frontend"}}}}}'
oc get pods -l tier=frontend
```

Don't add it to `spec.selector` — a Deployment's selector is immutable.

**Remember:** `hello.yaml` still says 3 replicas and has no `tier` label. If you re-apply it, those imperative changes are partly undone. On the exam, the cluster state is what gets graded; in real life, update the file.

Cleanup: `oc delete project lab21`

</details>

### Lab 2.3 — ConfigMap + Secret end-to-end (25 min)

In project `lab23`:

1. Create CM `appconfig` with `LOG_LEVEL=debug`, `GREETING=Hello`.
2. Create Secret `dbcreds` with `username=app`, `password=hunter2`.
3. Deploy `quay.io/openshifttest/hello-openshift:1.2.0` and use `oc set env` so:
   - The pod has `LOG_LEVEL` and `GREETING` from the CM
   - It has `DB_USERNAME` and `DB_PASSWORD` from the Secret (prefix `DB_`)
4. Verify the four variables are in the running pod (the image has no shell — see the note at the top of the Labs section).

<details>
<summary>💡 Solution Steps 1–2</summary>

```bash
oc new-project lab23

oc create configmap appconfig \
  --from-literal=LOG_LEVEL=debug \
  --from-literal=GREETING=Hello

oc create secret generic dbcreds \
  --from-literal=username=app \
  --from-literal=password=hunter2

oc get cm appconfig -o yaml
oc get secret dbcreds -o jsonpath='{.data.password}' | base64 -d; echo
# hunter2
```

</details>

<details>
<summary>💡 Solution Step 3</summary>

```bash
oc create deployment hello --image=quay.io/openshifttest/hello-openshift:1.2.0

oc set env deployment/hello --from=configmap/appconfig
oc set env deployment/hello --from=secret/dbcreds --prefix=DB_
```

`--from` creates one env var per key, upper-casing the key: `username` → `USERNAME`, and with `--prefix=DB_` → `DB_USERNAME`.

See what was generated:

```bash
oc set env deployment/hello --list
# # deployments/hello, container hello-openshift
# # LOG_LEVEL from configmap appconfig, key LOG_LEVEL
# # GREETING from configmap appconfig, key GREETING
# # DB_USERNAME from secret dbcreds, key username
# # DB_PASSWORD from secret dbcreds, key password
```

Under the hood these are `valueFrom.configMapKeyRef` / `secretKeyRef` entries — the YAML form from §3 and §4. The values are read when the pod **starts**, so later edits to the CM/Secret need `oc rollout restart deployment/hello`.

</details>

<details>
<summary>💡 Solution Step 4</summary>

```bash
oc rollout status deployment/hello

# Run `env` with the pod's spec but a UBI image that has a shell:
oc debug deployment/hello --image=registry.access.redhat.com/ubi9/ubi-minimal -- env \
  | grep -E 'LOG_|GREETING|DB_'
# LOG_LEVEL=debug
# GREETING=Hello
# DB_USERNAME=app
# DB_PASSWORD=hunter2
```

Alternative without starting a pod — read the spec:

```bash
oc get deployment hello -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}{"\n"}{end}'
```

(For an image that has a shell, `oc exec deploy/hello -- env | grep …` is the direct way.)

Cleanup: `oc delete project lab23`

</details>

### Lab 2.4 — Kustomize base + 2 overlays (40 min)

1. Build the directory layout from §5 (`base/`, `overlays/dev`, `overlays/prod`).
2. `base/` contains a Deployment and Service for the hello app, plus a generated ConfigMap `appconfig` (`LOG_LEVEL=info`, `GREETING=Hello`) that the Deployment loads with `envFrom`.
3. `dev` overlay: namespace `hello-dev`, replicas=1, label `env: dev`.
4. `prod` overlay: namespace `hello-prod`, replicas=5, label `env: prod`, merges `LOG_LEVEL=warn` into the CM, and **pins the image by digest** instead of a tag.
5. Apply both. `oc get deploy,svc,cm,po -n hello-prod` and `-n hello-dev`. Confirm the differences.
6. Delete both: `oc delete -k overlays/dev` and `oc delete -k overlays/prod`.

<details>
<summary>💡 Solution Steps 1–2 — the base</summary>

```bash
mkdir -p hello/{base,overlays/dev,overlays/prod} && cd hello
```

`base/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello
  labels:
    app: hello
spec:
  replicas: 2
  selector:
    matchLabels:
      app: hello
  template:
    metadata:
      labels:
        app: hello
    spec:
      containers:
        - name: hello
          image: quay.io/openshifttest/hello-openshift:1.2.0
          ports:
            - containerPort: 8080
          envFrom:
            - configMapRef:
                name: appconfig        # Kustomize rewrites this to the hashed name
          resources:
            requests: {cpu: 50m, memory: 64Mi}
            limits:   {cpu: 200m, memory: 128Mi}
```

`base/service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: hello
  labels:
    app: hello
spec:
  selector:
    app: hello
  ports:
    - port: 8080
      targetPort: 8080
```

`base/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
configMapGenerator:
  - name: appconfig
    literals:
      - LOG_LEVEL=info
      - GREETING=Hello
```

Check the base renders: `oc kustomize base/`

</details>

<details>
<summary>💡 Solution Step 3 — the dev overlay</summary>

`overlays/dev/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
namespace: hello-dev
labels:
  - pairs:
      env: dev
    includeTemplates: true     # pods get the label too; selectors stay untouched
replicas:
  - name: hello
    count: 1
```

The `replicas:` transformer is the shortest way to change a replica count — no patch file needed.

</details>

<details>
<summary>💡 Solution Step 4 — the prod overlay</summary>

First get the digest that the `1.2.0` tag points to. The simplest reliable way is to read it from a running pod (deploy dev first — Step 5):

```bash
oc get pod -n hello-dev -l app=hello \
  -o jsonpath='{.items[0].status.containerStatuses[0].imageID}{"\n"}'
# quay.io/openshifttest/hello-openshift@sha256:4f3b…   ← copy the sha256:… part
```

(`oc image info quay.io/openshifttest/hello-openshift:1.2.0` also shows digests, but for multi-arch images it asks for `--filter-by-os` and then gives the per-architecture digest.)

`overlays/prod/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
namespace: hello-prod
labels:
  - pairs:
      env: prod
    includeTemplates: true
patches:
  - path: replicas-patch.yaml
images:
  - name: quay.io/openshifttest/hello-openshift
    digest: sha256:<paste-the-digest-here>
configMapGenerator:
  - name: appconfig
    behavior: merge
    literals:
      - LOG_LEVEL=warn
```

`overlays/prod/replicas-patch.yaml` (strategic merge patch — matched to the Deployment by kind + name):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello
spec:
  replicas: 5
```

Preview before applying — check the image line, the replica count and the merged CM:

```bash
oc kustomize overlays/prod | grep -E 'image:|replicas:|LOG_LEVEL|name: appconfig'
#   LOG_LEVEL: warn
#   name: appconfig-m87d62t9k4
#   replicas: 5
#             name: appconfig-m87d62t9k4
#         image: quay.io/openshifttest/hello-openshift@sha256:…
```

**Why a digest:** a tag can be moved to a different image; a digest can't. Pinning prod by digest means it only changes when you change the overlay. (To change the tag instead, use `newTag:`.)

</details>

<details>
<summary>💡 Solution Step 5 — apply and compare</summary>

`namespace:` doesn't create namespaces, so create them first:

```bash
oc new-project hello-dev
oc new-project hello-prod

oc apply -k overlays/dev
oc apply -k overlays/prod

oc get deploy,svc,cm,po -n hello-dev
oc get deploy,svc,cm,po -n hello-prod
```

What to confirm:

| Check | dev | prod |
|-------|-----|------|
| `oc get deploy hello -o jsonpath='{.spec.replicas}'` | `1` | `5` |
| `oc get pods -l env=<env>` | 1 pod | 5 pods |
| `oc get cm -o name` | `appconfig-<hash1>` | `appconfig-<hash2>` (different hash — different content) |
| `LOG_LEVEL` in the CM | `info` | `warn` |
| Image | `…:1.2.0` | `…@sha256:…` |

```bash
oc get cm -n hello-prod -o yaml | grep LOG_LEVEL
oc get deploy hello -n hello-prod -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

**Try it:** change `LOG_LEVEL=warn` to `LOG_LEVEL=error` in the prod overlay and re-apply. The CM gets a new hash name, the Deployment's reference changes, and the pods roll automatically.

</details>

<details>
<summary>💡 Solution Step 6 — cleanup</summary>

```bash
oc delete -k overlays/dev
oc delete -k overlays/prod
# deletes exactly what each overlay rendered

oc delete project hello-dev hello-prod
```

Old generated ConfigMaps (previous hashes) aren't deleted by `oc apply -k`; they're removed here with the namespace, or by hand with `oc delete cm <old-name>`.

</details>

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

Swap `4.18` for your exam's version. Guide index pages are the most stable entry points; use the left-hand navigation from there.

- Building applications (Deployments, config maps, secrets): <https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/building_applications/index>
- Nodes (pods, config maps & secrets as volumes/env, resource limits): <https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/nodes/index>
- CLI tools (`oc` reference, including `oc kustomize` / `oc apply -k`): <https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/cli_tools/index>
- Upstream Kustomize reference: <https://kubectl.docs.kubernetes.io/references/kustomize/>

---

<div align="center">

[⬅️ Prev: Manage OpenShift Container Platform](./01-manage-ocp.md) &nbsp;·&nbsp; [🏠 Home](../README.md) &nbsp;·&nbsp; [Next: Deploy applications ➡️](./03-deploy-applications.md)

</div>
