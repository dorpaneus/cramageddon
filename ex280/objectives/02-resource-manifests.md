<div align="center">

[⬅️ Prev: Manage OpenShift Container Platform](./01-manage-ocp.md) &nbsp;·&nbsp; [🏠 Home](../README.md) &nbsp;·&nbsp; [Next: Deploy applications ➡️](./03-deploy-applications.md)

</div>

# Objective 2 - Work with Resource Manifests

> **Exam study points (OCP 4.18–4.22):**
> - Deploy applications from YAML resource manifests
> - Update application deployments
> - Deploy applications using Kustomize
> - Work with Kustomize overlays
> - Create and use secrets
> - Create and use configuration maps

`oc` is built on `kubectl`, so everything Kubernetes-native works here. The big OCP-specific advantages in this objective are `oc set data`, `oc extract`, `oc set volume`, Routes, ImageStreams, and integrated Kustomize support (`oc apply -k`).

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
oc explain pod.spec.containers.livenessProbe
oc explain --recursive deployment.spec | less
```

## §2 — Updating deployments

```bash
# Image rollout
oc set image deployment/hello hello=quay.io/openshifttest/hello-openshift:1.3.0
oc rollout status deployment/hello
oc rollout history deployment/hello
oc rollout undo deployment/hello                   # rollback to previous
oc rollout undo deployment/hello --to-revision=3
oc rollout restart deployment/hello                # force fresh pod creation

# Environment variables
oc set env deployment/hello LOG_LEVEL=debug
oc set env deployment/hello --list
oc set env deployment/hello LOG_LEVEL-             # unset (note trailing -)

# From a ConfigMap / Secret
oc set env deployment/hello --from=configmap/appconfig
oc set env deployment/hello --from=secret/dbcreds --prefix=DB_

# Replicas
oc scale deployment/hello --replicas=5

# Resources
oc set resources deployment/hello --limits=cpu=500m,memory=256Mi --requests=cpu=100m,memory=64Mi

# Probes (OpenShift-specific CLI time-saver!)
oc set probe deployment/hello --readiness --get-url=http://:8080/ --initial-delay-seconds=5
oc set probe deployment/hello --liveness --open-tcp=8080 --initial-delay-seconds=10

# Pause / resume rollouts (batch multiple changes into a single rollout)
oc rollout pause deployment/hello
# … run several `oc set` commands without triggering intermediate ReplicaSets …
oc rollout resume deployment/hello
```

### `oc set volume` (Huge Exam Time-Saver)

Instead of hand-writing `volumes:` and `volumeMounts:` YAML blocks and risking indentation errors, let `oc set volume` mutate the Deployment for you:

```bash
# Mount a secret as a directory of files
oc set volume deployment/hello --add --type=secret --secret-name=tls \
  --mount-path=/etc/tls --name=tls-vol

# Mount a ConfigMap as a directory of files
oc set volume deployment/hello --add --type=configmap --configmap-name=appconfig \
  --mount-path=/etc/config --name=cfg-vol

# Mount a PVC (and even create the PVC on the fly if --claim-size is passed!)
oc set volume deployment/hello --add --type=pvc --claim-name=data \
  --claim-size=2Gi --claim-mode=ReadWriteOnce --mount-path=/var/lib/data --name=data

# List volumes on a deployment
oc set volume deployment/hello

# Remove a volume
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

# Create from a file with a custom key name
oc create configmap nginx-conf --from-file=custom.conf=nginx.conf

# Create from an env file (each KEY=VAL line becomes a key)
oc create configmap env-cfg --from-env-file=app.env

# Update or add keys in-place without editing YAML (OCP superpower!)
oc set data configmap/appconfig LOG_LEVEL=debug NEW_KEY=enabled
oc set data configmap/appconfig --from-file=nginx.conf

# Extract ConfigMap keys to stdout or a directory
oc extract configmap/appconfig --to=-
oc extract configmap/appconfig --to=/tmp/cfg-out

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
# 1. As env vars (all keys imported with their exact ConfigMap key names)
spec:
  containers:
    - name: app
      envFrom:
        - configMapRef:
            name: appconfig
```

```yaml
# 2. As individual env vars (use when remapping key names!)
env:
  - name: APP_LOG_LEVEL
    valueFrom:
      configMapKeyRef:
        name: appconfig
        key: LOG_LEVEL
```

```yaml
# 3. As mounted files (or use `oc set volume`!)
volumes:
  - name: cfg
    configMap:
      name: appconfig
volumeMounts:
  - name: cfg
    mountPath: /etc/app
    # subPath: app.properties  # Use subPath if mounting a single file without hiding existing dir contents
```

## §4 — Secrets

Same shape as ConfigMaps but **base64-encoded** (or `stringData` in plain text when writing YAML) and treated separately by RBAC/audit.

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

# Update Secret keys in-place (auto-encodes to base64!)
oc set data secret/dbcreds password=newpass

# Decode & inspect Secrets the fast way with `oc extract`
oc extract secret/dbcreds --to=-                  # prints decoded values to terminal!
oc extract secret/mytls --to=/tmp/tls --confirm   # writes tls.crt and tls.key to /tmp/tls

# Decode a single key via jsonpath
oc get secret dbcreds -o jsonpath='{.data.password}' | base64 -d ; echo
```

### Built-in secret types

| Type | CLI subcommand | Used for |
|------|----------------|----------|
| `Opaque` | `oc create secret generic` | Arbitrary key/value pairs |
| `kubernetes.io/tls` | `oc create secret tls` | TLS `tls.crt` + `tls.key` |
| `kubernetes.io/dockerconfigjson` | `oc create secret docker-registry` | Registry pull credentials |
| `kubernetes.io/basic-auth` | *(YAML `type:`)* | `username` / `password` pair |
| `kubernetes.io/ssh-auth` | `oc create secret generic --from-file=ssh-privatekey=...` | SSH private key |

### Consuming a Secret

```yaml
# As env var (remapping key 'password' -> 'DB_PASSWORD')
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
      defaultMode: 0400        # octal 0400 (256 in decimal) restricts file permissions
volumeMounts:
  - name: creds
    mountPath: /etc/creds
    readOnly: true
```

> 🛡️ **Pod Security Admission (PSA) note (OCP 4.18–4.22):** The `restricted-v2` SCC and `restricted` PSA profile are enforced by default. When you create a standard Deployment and mount Secrets/ConfigMaps, OpenShift automatically injects the required securityContext (`runAsNonRoot: true`, random UID from namespace range, `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]`) **unless** the container image hardcodes `USER 0` (root) or tries to write to root-owned directories like `/var/cache/nginx`. See `09-application-security.md`.

## §5 — Kustomize basics

`oc` ships Kustomize natively (`oc apply -k` and `oc kustomize`). The entry point is always named `kustomization.yaml`.

### A clean base + overlay layout

```text
myapp/
├── base/
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   └── service.yaml
└── overlays/
    ├── dev/
    │   └── kustomization.yaml
    └── prod/
        ├── kustomization.yaml
        └── replicas-patch.yaml
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
generatorOptions:
  disableNameSuffixHash: true    # Keep exact name 'appconfig' if Deployment references it statically
labels:
  - pairs:
      app: hello
    includeSelectors: true       # Safe in base when creating initial selectors
```

### Apply / preview

```bash
# Always preview the rendered YAML before applying!
oc kustomize base/
oc kustomize overlays/prod/

# Apply
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
  - ../../base                     # inherit from base
namespace: myapp-prod
nameSuffix: -prod
labels:
  - pairs:
      env: prod
    includeSelectors: false        # CRITICAL in overlays: don't mutate immutable Deployment matchLabels!
    includeTemplates: true         # Do apply label to Pod template metadata
patches:
  - path: replicas-patch.yaml
    target:
      kind: Deployment
      name: hello
images:
  - name: quay.io/openshifttest/hello-openshift
    newTag: "1.3.0"
configMapGenerator:
  - name: appconfig
    behavior: merge                # Works because base used configMapGenerator!
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

> 💡 **Pro Tip — Built-in `replicas:` transformer:** If an exam question only asks you to change the replica count in a Kustomize overlay without requiring a patch file, you don't even need `replicas-patch.yaml`! Just put this directly inside `kustomization.yaml`:
> ```yaml
> replicas:
>   - name: hello
>     count: 5
> ```

---

## 🧪 Labs

### Lab 2.1 — From scratch to running (20 min)

1. Create project `lab21`. Generate a Deployment manifest (`hello.yaml`) for `quay.io/openshifttest/hello-openshift:1.2.0`, 3 replicas, port 8080.
2. Add resource requests (`50m` CPU, `64Mi` memory) and limits (`200m` CPU, `128Mi` memory).
3. Apply and verify 3 pods are running.
4. Expose the Deployment via a `ClusterIP` Service (port 8080 → targetPort 8080).
5. Expose the Service via a standard HTTP Route and `curl` it.

<details>
<summary>💡 Solution Lab 2.1</summary>

```bash
# 1. Create project & generate base YAML
oc new-project lab21
oc create deployment hello \
  --image=quay.io/openshifttest/hello-openshift:1.2.0 \
  --replicas=3 --port=8080 \
  --dry-run=client -o yaml > hello.yaml

# 2 & 3. Apply the Deployment and set resources (or edit hello.yaml directly)
oc apply -f hello.yaml
oc set resources deployment/hello --requests=cpu=50m,memory=64Mi --limits=cpu=200m,memory=128Mi
oc rollout status deployment/hello

# 4. Expose as a ClusterIP Service
oc expose deployment/hello --port=8080 --target-port=8080

# 5. Expose Service as a Route and test
oc expose service/hello
ROUTE_HOST=$(oc get route hello -o jsonpath='{.spec.host}')
curl -s http://$ROUTE_HOST
# Output: Hello OpenShift!
```
</details>

---

### Lab 2.2 — Patch storm (15 min)

In `lab21`:

1. Update the image to a non-existing tag (`:broken`) via `oc set image`, and watch the rollout stall.
2. Roll back with `oc rollout undo` and confirm the old image (`:1.2.0`) is back.
3. Change replicas to 5 with `oc patch`.
4. Add a label `tier=frontend` to the Deployment metadata and Pod template.

<details>
<summary>💡 Solution Lab 2.2</summary>

```bash
# 1. Break the image
oc set image deployment/hello hello-openshift=quay.io/openshifttest/hello-openshift:broken
oc get pods -l app=hello
# New pod shows ErrImagePull / ImagePullBackOff

# 2. Undo rollout
oc rollout undo deployment/hello
oc rollout status deployment/hello
oc get deployment hello -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
# Output: quay.io/openshifttest/hello-openshift:1.2.0

# 3. Patch replicas to 5
oc patch deployment hello --type=merge -p '{"spec":{"replicas":5}}'

# 4. Add label to Deployment
oc label deployment/hello tier=frontend
```
</details>

---

### Lab 2.3 — ConfigMap + Secret end-to-end (25 min)

In project `lab23`:

1. Create ConfigMap `appconfig` with `LOG_LEVEL=debug`, `GREETING=Hello`.
2. Create Secret `dbcreds` with `USERNAME=app`, `PASSWORD=hunter2`.
3. Deploy `quay.io/openshifttest/hello-openshift:1.2.0` (`deploy/hello`) and use `oc set env` so:
   - The pod has `LOG_LEVEL` and `GREETING` from `appconfig`
   - It has `DB_USERNAME` and `DB_PASSWORD` from `dbcreds` (using `--prefix=DB_`)
4. Mount `appconfig` as files inside `/etc/config` using `oc set volume`.
5. Verify both the environment variables and mounted files using `oc exec`.

<details>
<summary>💡 Solution Lab 2.3</summary>

```bash
oc new-project lab23

# 1 & 2. Create ConfigMap and Secret
oc create cm appconfig --from-literal=LOG_LEVEL=debug --from-literal=GREETING=Hello
oc create secret generic dbcreds --from-literal=USERNAME=app --from-literal=PASSWORD=hunter2

# 3. Deploy and inject env vars
oc create deployment hello --image=quay.io/openshifttest/hello-openshift:1.2.0
oc set env deployment/hello --from=configmap/appconfig
oc set env deployment/hello --from=secret/dbcreds --prefix=DB_

# 4. Mount ConfigMap as volume
oc set volume deployment/hello --add --type=configmap --configmap-name=appconfig \
  --mount-path=/etc/config --name=cfg-vol

oc rollout status deployment/hello

# 5. Verify
oc exec deploy/hello -- env | grep -E 'LOG_LEVEL|GREETING|DB_'
oc exec deploy/hello -- ls -l /etc/config
```

> ⚠️ **Exam Watchout:** If the exam pre-creates a Secret with lowercase keys (`username`, `password`) and asks for uppercase env vars (`DB_USERNAME`, `DB_PASSWORD`), `--prefix=DB_` will produce `DB_username`! In that case, map keys explicitly in YAML (`secretKeyRef`) or via `oc patch`.
</details>

---

### Lab 2.4 — Kustomize base + 2 overlays (40 min)

1. Build the directory layout (`base/`, `overlays/dev`, `overlays/prod`) in `/tmp/lab24`.
2. `base/` contains a Deployment, Service, and `configMapGenerator` for `appconfig` (`LOG_LEVEL=info`).
3. `dev` overlay deploys to `hello-dev`, sets `replicas=1`, and adds label `env: dev`.
4. `prod` overlay deploys to `hello-prod`, sets `replicas=5`, adds label `env: prod`, bumps image tag to `1.3.0`, and merges `LOG_LEVEL=warn` into `appconfig`.
5. Create `hello-dev` and `hello-prod` projects, apply both overlays, and verify differences.
6. Clean up both projects.

<details>
<summary>💡 Solution Lab 2.4</summary>

```bash
mkdir -p /tmp/lab24/{base,overlays/dev,overlays/prod}
cd /tmp/lab24

# Generate base manifests
oc create deployment hello --image=quay.io/openshifttest/hello-openshift:1.2.0 \
  --port=8080 --dry-run=client -o yaml > base/deployment.yaml
oc create service clusterip hello --tcp=8080:8080 \
  --dry-run=client -o yaml > base/service.yaml

cat <<EOF> base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
configMapGenerator:
  - name: appconfig
    literals:
      - LOG_LEVEL=info
generatorOptions:
  disableNameSuffixHash: true
EOF

# Dev overlay
cat <<EOF> overlays/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
namespace: hello-dev
labels:
  - pairs:
      env: dev
    includeSelectors: false
    includeTemplates: true
replicas:
  - name: hello
    count: 1
EOF

# Prod overlay
cat <<EOF> overlays/prod/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
namespace: hello-prod
labels:
  - pairs:
      env: prod
    includeSelectors: false
    includeTemplates: true
replicas:
  - name: hello
    count: 5
images:
  - name: quay.io/openshifttest/hello-openshift
    newTag: "1.3.0"
configMapGenerator:
  - name: appconfig
    behavior: merge
    literals:
      - LOG_LEVEL=warn
EOF

# Create namespaces & apply
oc new
