# Week 1 Mock Exam — 30 minutes — Objectives 1–2

**Cluster:** OCP 4.18 – 4.22 (CRC / OpenShift Local or Dedicated Lab).
**Reference allowed:** Only the official OpenShift documentation at <https://docs.redhat.com/en/documentation/openshift_container_platform/>.
**Rules:** Timer running, single browser tab for docs, no AI / no Google. Take a 5-minute break before reviewing the answer key.

You will be graded on whether the **end state** matches the exact specification, not how you got there. All work must persist if you run `oc rollout restart` on the deployment.

---

## 🧪 Tasks (30 minutes total)

### Task 1 — Project setup (3 min) — 30 points

Create a project named exactly **`mock1-app`** with the display name `"Week 1 Mock"`. Switch into it. All subsequent tasks happen there unless stated otherwise.

### Task 2 — Deploy from YAML (5 min) — 60 points

Apply a Deployment named **`hello`** in `mock1-app`:

- Image: `quay.io/openshifttest/hello-openshift:1.2.0`
- Replicas: **3**
- Container port: **8080**
- Pod & Deployment Labels: `app=hello`, `env=mock`
- Resource requests: `100m` CPU, `64Mi` memory
- Resource limits: `500m` CPU, `256Mi` memory

Then expose it via a `ClusterIP` Service called **`hello`** on port `8080` → targetPort `8080`.

Verify: `oc get pods -l app=hello` shows 3 Ready, and `oc get endpoints hello` shows 3 endpoints.

### Task 3 — Query & filter (3 min) — 30 points

Without using `grep`, `awk`, or `sed`, produce a list of pods cluster-wide whose `status.phase` is `Running`, formatted strictly as `NAMESPACE/NAME` (one per line), using `-o jsonpath`. Save the output of the command in `/tmp/running-pods.txt`.

### Task 4 — ConfigMap + Secret consumption (8 min) — 80 points

In namespace `mock1-app`, create:

- ConfigMap **`app-config`** with keys: `LOG_LEVEL=info`, `GREETING=Hello-EX280`.
- Secret **`api-creds`** with keys: `username=app`, `password=hunter2` (use `generic` type).

Update the `hello` Deployment so that every pod has:

- `LOG_LEVEL` and `GREETING` injected from the ConfigMap (environment variables with the **exact same names**)
- **`DB_USERNAME`** mapped to the `username` key of Secret `api-creds`, and **`DB_PASSWORD`** mapped to the `password` key of Secret `api-creds` *(Watch out for case sensitivity!)*

Verify with `oc exec deploy/hello -- env | grep -E 'LOG_|GREETING|DB_'` — all four uppercase variables must appear.

### Task 5 — Kustomize overlay (11 min) — 100 points

Create the following directory structure on your workstation:

```text
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

- `base/` reproduces the `hello` Deployment + Service from Task 2, and sets `namespace: mock1-prod` in `kustomization.yaml`.
- The **prod overlay**:
  - Sets `replicas` to **5** (via a strategic-merge patch in `replicas-patch.yaml`).
  - Adds the label `tier=production` to all resources without mutating immutable Deployment selectors (`includeSelectors: false`).
  - Updates the image tag to `quay.io/openshifttest/hello-openshift:1.3.0` (via the Kustomize `images:` transformer).
- Create the `mock1-prod` namespace beforehand (`oc new-project mock1-prod`) and apply the overlay using `oc apply -k overlays/prod/`.

Verify: `oc get deploy hello -n mock1-prod -o yaml` shows 5 replicas, the `1.3.0` image tag, and the `tier: production` label.

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
  labels:
    app: hello
    env: mock
spec:
  replicas: 3
  selector:
    matchLabels:
      app: hello
  template:
    metadata:
      labels:
        app: hello
        env: mock
    spec:
      containers:
        - name: hello
          image: quay.io/openshifttest/hello-openshift:1.2.0
          ports:
            - containerPort: 8080
          resources:
            requests:
              cpu: 100m
              memory: 64Mi
            limits:
              cpu: 500m
              memory: 256Mi
EOF

oc expose deploy/hello --port=8080 --target-port=8080 --name=hello
```

### Task 3

```bash
oc get pods -A --field-selector=status.phase=Running \
  -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{"\n"}{end}' > /tmp/running-pods.txt
```

### Task 4

```bash
oc create cm app-config --from-literal=LOG_LEVEL=info --from-literal=GREETING=Hello-EX280
oc create secret generic api-creds --from-literal=username=app --from-literal=password=hunter2

# Inject ConfigMap keys directly (names already match)
oc set env deploy/hello --from=configmap/app-config

# Because the Secret keys are lowercase (username/password) and the target env vars are uppercase
# (DB_USERNAME/DB_PASSWORD), --prefix=DB_ would produce DB_username (wrong case!).
# Patch explicit secretKeyRef entries instead:
oc patch deploy/hello --type=json -p='[
  {"op":"add","path":"/spec/template/spec/containers/0/env","value":[
    {"name":"DB_USERNAME","valueFrom":{"secretKeyRef":{"name":"api-creds","key":"username"}}},
    {"name":"DB_PASSWORD","valueFrom":{"secretKeyRef":{"name":"api-creds","key":"password"}}}
  ]}
]'

# Verify
oc rollout status deploy/hello
oc exec deploy/hello -- env | grep -E 'LOG_|GREETING|DB_'
```

### Task 5

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
labels:
  - pairs:
      tier: production
    includeSelectors: false
patches:
  - path: replicas-patch.yaml
    target:
      kind: Deployment
      name: hello
images:
  - name: quay.io/openshifttest/hello-openshift
    newTag: "1.3.0"
```

`overlays/prod/replicas-patch.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello
spec:
  replicas: 5
```

Apply and verify:

```bash
oc new-project mock1-prod
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
| 3 — Query (`NAMESPACE/NAME`) | 30 | |
| 4 — CM + Secret env injection (case-exact) | 80 | |
| 5 — Kustomize overlay | 100 | |
