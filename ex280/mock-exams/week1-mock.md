# Week 1 Mock Exam — 30 minutes — Objectives 1–2

**Cluster:** OCP 4.18 (CRC, Developer Sandbox, or your own).
**Reference allowed:** Only <https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/>.
**Rules:** Timer running, single browser tab for docs, no AI / no Google. Take a 5-min break before reviewing the answer key.

You will be graded on whether the **end state** matches the description, not how you got there. All work must persist if you `oc rollout restart` the deployment.

---

## 🧪 Tasks (30 minutes total)

### Task 1 — Project setup (3 min) — 30 points

Create a project named exactly **`mock1-app`** with the display name `"Week 1 Mock"`. Switch into it. All subsequent tasks happen there unless stated otherwise.

### Task 2 — Deploy from YAML (5 min) — 60 points

Apply a Deployment named **`hello`**:

- Image: `quay.io/openshifttest/hello-openshift:1.2.0`
- Replicas: **3**
- Container port: **8080**
- Labels: `app=hello`, `env=mock`
- Resource requests: `100m` CPU, `64Mi` memory
- Resource limits: `500m` CPU, `256Mi` memory

Then expose it via a `ClusterIP` Service called **`hello`** on port `8080` → targetPort `8080`.

Verify: `oc get pods -l app=hello` shows 3 Ready, and `oc get endpoints hello` shows 3 endpoints.

### Task 3 — Query & filter (3 min) — 30 points

Without using `grep` or `awk`, produce a list of pods cluster-wide whose `status.phase` is `Running`, formatted as `NAMESPACE/NAME`, using `-o jsonpath` or `-o custom-columns`. Save the output of the command in `/tmp/running-pods.txt`.

### Task 4 — ConfigMap + Secret consumption (8 min) — 80 points

Create:

- ConfigMap **`app-config`** with keys: `LOG_LEVEL=info`, `GREETING=Hello-EX280`.
- Secret **`api-creds`** with keys: `username=app`, `password=hunter2` (use `generic` type).

Patch the `hello` Deployment so that every pod has:

- `LOG_LEVEL` and `GREETING` from the ConfigMap (env vars with the **same names**)
- `DB_USERNAME` and `DB_PASSWORD` from the Secret (env vars with the `DB_` prefix)

Verify by `oc rsh` and `env | grep -E 'LOG_|GREETING|DB_'` — all four should appear.

### Task 5 — Kustomize overlay (11 min) — 100 points

Create the following directory structure on your workstation:

```
mock1-kustomize/
├── base/
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   └── service.yaml
└── overlays/
    └── prod/
        ├── kustomization.yaml
        └── replicas-patch.yaml
```

- `base/` reproduces the `hello` Deployment + Service from Task 2, but **into namespace `mock1-prod`** (don't create the namespace yet — let Kustomize do it via `namespace:`).
- The **prod overlay**:
  - Sets `replicas` to **5** (via a strategic-merge patch).
  - Adds the label `tier=production` to every resource.
  - Bumps the image to `quay.io/openshifttest/hello-openshift:1.3.0` (via `images:` transformer).
- Create the `mock1-prod` namespace beforehand: `oc create namespace mock1-prod`.
- `oc apply -k overlays/prod/`.

Verify: `oc get deploy hello -n mock1-prod -o yaml` shows 5 replicas, the new image, and `tier=production`.

---

## ⏱️ When the timer hits zero — STOP

Take 5 minutes off, then walk through the answer key below.

---

## ✅ Answer Key (don't read until you've finished or run out of time)

<details>
<summary>Click to expand</summary>

### Task 1

```bash
oc new-project mock1-app --display-name="Week 1 Mock"
oc project mock1-app
```

### Task 2

```bash
cat <<EOF | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello
  labels: {app: hello, env: mock}
spec:
  replicas: 3
  selector: {matchLabels: {app: hello}}
  template:
    metadata: {labels: {app: hello, env: mock}}
    spec:
      containers:
        - name: hello
          image: quay.io/openshifttest/hello-openshift:1.2.0
          ports: [{containerPort: 8080}]
          resources:
            requests: {cpu: 100m, memory: 64Mi}
            limits:   {cpu: 500m, memory: 256Mi}
EOF

oc expose deploy/hello --port=8080 --target-port=8080 --name=hello
```

### Task 3

```bash
oc get pods -A --field-selector=status.phase=Running \
  -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name \
  --no-headers > /tmp/running-pods.txt
```

### Task 4

```bash
oc create cm  app-config --from-literal=LOG_LEVEL=info --from-literal=GREETING=Hello-EX280
oc create secret generic api-creds --from-literal=username=app --from-literal=password=hunter2

oc set env deploy/hello --from=configmap/app-config
oc set env deploy/hello --from=secret/api-creds --prefix=DB_

# Verify
oc rsh deploy/hello env | grep -E 'LOG_|GREETING|DB_'
```

### Task 5

`base/deployment.yaml` and `base/service.yaml` are the same YAMLs from Task 2.

`base/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: mock1-prod
resources:
  - deployment.yaml
  - service.yaml
```

`overlays/prod/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
commonLabels:
  tier: production
patches:
  - path: replicas-patch.yaml
    target: {kind: Deployment, name: hello}
images:
  - name: quay.io/openshifttest/hello-openshift
    newTag: "1.3.0"
```

`overlays/prod/replicas-patch.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: {name: hello}
spec:
  replicas: 5
```

Apply:

```bash
oc create namespace mock1-prod
oc apply -k overlays/prod/
oc get deploy hello -n mock1-prod -o yaml | grep -E 'replicas:|image:|tier:'
```

</details>

---

## 📊 Score yourself

Total: **300 points**. Passing: **210 (70%)**.

| Task | Points | Got it? |
|------|--------|---------|
| 1 — Project | 30 | |
| 2 — Deployment + Service | 60 | |
| 3 — Query | 30 | |
| 4 — CM + Secret env injection | 80 | |
| 5 — Kustomize overlay | 100 | |

Add a row to the bottom of `01-manage-ocp.md` or `02-resource-manifests.md` under a "Gaps from Mock Week 1" heading for anything below 100% — then drill it before next week.
