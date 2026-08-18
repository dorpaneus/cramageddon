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

1. Generate a Deployment manifest for `quay.io/openshifttest/hello-openshift:1.2.0`, 3 replicas, port 8080, into project `lab21`.
2. Add resource requests/limits.
3. Apply, verify pods running.
4. Add a Service (port 8080 → targetPort 8080) and apply.
5. Expose via Route, `curl` it.

### Lab 2.2 — Patch storm (15 min)

In `lab21`:

1. Update the image to a non-existing tag via `oc set image`, watch the rollout fail.
2. `oc rollout undo` and confirm the old image is back.
3. Change replicas to 5 with `oc patch`.
4. Add a label `tier=frontend` to the deployment with `oc label`.

### Lab 2.3 — ConfigMap + Secret end-to-end (25 min)

In project `lab23`:

1. Create CM `appconfig` with `LOG_LEVEL=debug`, `GREETING=Hello`.
2. Create Secret `dbcreds` with `username=app`, `password=hunter2`.
3. Deploy `quay.io/openshifttest/hello-openshift:1.2.0` and use `oc set env` so:
   - The pod has `LOG_LEVEL` and `GREETING` from the CM
   - It has `DB_USERNAME` and `DB_PASSWORD` from the Secret (prefix `DB_`)
4. `oc rsh` into the pod and `env | grep -E 'LOG_|GREETING|DB_'` to verify.

### Lab 2.4 — Kustomize base + 2 overlays (40 min)

1. Build the directory layout above (`base/`, `overlays/dev`, `overlays/prod`).
2. `base/` contains a Deployment, Service, ConfigMap for the hello app.
3. `dev` overlay sets replicas=1 and adds label `env: dev`.
4. `prod` overlay sets replicas=5, adds label `env: prod`, bumps image tag to `1.3.0`, merges `LOG_LEVEL=warn` into the CM, deploys to namespace `hello-prod`.
5. Apply both. `oc get deploy,svc,cm,po -n hello-prod` and `-n hello-dev`. Confirm differences.
6. Delete both: `oc delete -k overlays/dev` and `oc delete -k overlays/prod`.

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

- Working with manifests: `…/building_applications/working-with-projects`
- ConfigMaps & Secrets: `…/nodes/pods/nodes-pods-configmaps` and `…/nodes/pods/nodes-pods-secrets`
- Kustomize in `oc`: `…/cli_tools/openshift-cli-oc/managing-cli-plug-ins` (and the upstream <https://kustomize.io>)
---

<div align="center">

[⬅️ Prev](../README.md) &nbsp;·&nbsp; [🏠 Home](../README.md) &nbsp;·&nbsp; [Next: Day 2 ➡️](./day-02-processes-proc-signals.md)

</div>
