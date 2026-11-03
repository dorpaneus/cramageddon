# Portfolio Challenge 02: Declarative AI Inference Gateway with Kustomize

## 🎯 Scenario (What You Will Present in Interviews)
Your AI Platform team operates a unified **LLM Inference Gateway** (a proxy sitting in front of model-serving backends like vLLM or OpenAI-compatible APIs). You need to manage this service across two environments (`ai-gateway-dev` and `ai-gateway-prod`) using **GitOps-ready Kustomize bases and overlays** with zero duplicated YAML.

## 📋 Technical Requirements to Build

Create the directory structure under `platform-lab/02-kustomize-ai-gateway/`:
- `base/`
- `overlays/dev/`
- `overlays/prod/`

### 1. The Base (`base/`)
- **Deployment (`ai-gateway`):**
  - Uses image `quay.io/openshifttest/hello-openshift:1.2.0` (acting as our lightweight mock HTTP inference proxy on port `8080`).
  - Sets default resource requests (`100m` CPU, `128Mi` RAM) and limits (`250m` CPU, `256Mi` RAM).
  - Configures a **Readiness Probe** (HTTP GET on `/` port `8080`) and **Liveness Probe** (TCP socket on `8080`).
- **Service (`ai-gateway`):**
  - Exposes port `8080` internally as `ClusterIP`.
- **ConfigMap Generator (`gateway-config`):**
  - Generated via `configMapGenerator` (with `disableNameSuffixHash: true`).
  - Keys: `MODEL_BACKEND_URL=http://vllm-service:8000`, `LOG_LEVEL=info`, `MAX_TOKENS=2048`.
  - Mount this ConfigMap into the Deployment at `/etc/ai-gateway/config` **AND** expose `LOG_LEVEL` as an environment variable.

### 2. The Dev Overlay (`overlays/dev/`)
- Targets namespace `ai-gateway-dev`.
- Sets `replicas` to `1`.
- Adds label `environment: development` to all resources **without** mutating immutable Deployment `matchLabels`.
- Overrides `LOG_LEVEL=debug` in `gateway-config` using `behavior: merge`.

### 3. The Prod Overlay (`overlays/prod/`)
- Targets namespace `ai-gateway-prod`.
- Sets `replicas` to `3`.
- Adds label `environment: production` safely.
- Uses the `images:` transformer to pin the image to an **immutable SHA256 digest** (use the digest you found in Challenge 01, or `newTag: "1.3.0"`).
- Uses a **Strategic Merge Patch** (`resources-patch.yaml`) to increase prod limits to `1000m` CPU and `1Gi` RAM.
- Uses `secretGenerator` (or a pre-created Secret reference) to inject an environment variable `UPSTREAM_API_KEY` into the prod container.

## 🔍 What You Need to Research & Read
1. **Kustomize `labels` vs `commonLabels`:** Run `oc kustomize` and inspect how `includeSelectors: false` and `includeTemplates: true` behave on a `Deployment`.
2. **Kustomize `configMapGenerator` Merging:** Read how `behavior: merge` in an overlay interacts with `base/kustomization.yaml`.
3. **Strategic Merge Patch for Container Resources:** Remember that `spec.template.spec.containers` is a YAML list—what field is required inside `containers:` in your patch file so Kustomize knows *which* container to merge the new CPU/Memory limits into?

## ✅ Verification Criteria
When you run `oc kustomize overlays/prod/`, it must render cleanly with zero warnings, and `oc apply -k overlays/prod/` must bring up 3 Ready pods with `/etc/ai-gateway/config/LOG_LEVEL` equal to `info` (or `warn`) and `1Gi` memory limits.
