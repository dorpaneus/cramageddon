<div align="center">

[🏠 Home](./README.md) &nbsp;·&nbsp; [🎯 Obj 1: Manage OCP](./objectives/01-manage-ocp.md) &nbsp;·&nbsp; [⚙️ Obj 2: Resource Manifests](./objectives/02-resource-manifests.md)

</div>

# ⚡ EX280 Exam Speed-Run & Time-Saver Cheatsheet (OCP 4.18 – 4.22)

> **Goal:** Save 30–45 minutes on exam day by eliminating repetitive typing, avoiding manual YAML indentation errors in `vim`, and letting `oc` generate and mutate manifests for you.

---

## 🅰️ Step A — The First 90 Seconds: Bootstrap `~/.bashrc` & `~/.vimrc`

Before reading Question 1 on the exam, open your terminal and configure your shell and editor. This takes 90 seconds and prevents fatal YAML syntax mistakes for the next 3 hours.

### 1. Shell Aliases & Environment Variables (`~/.bashrc`)

Copy or type this block into `~/.bashrc` and reload with `source ~/.bashrc`:

```bash
cat << 'EOF' >> ~/.bashrc
# 1. Ensure bash completion is active for 'oc' and 'k'
source <(oc completion bash)
alias k='oc'
complete -o default -F __start_oc k

# 2. The Golden Exam Exports
export do='--dry-run=client -o yaml'
export now='--force --grace-period=0'

# 3. High-Speed Inspection Aliases
alias oget='oc get all,cm,secret,pvc,netpol,quota,limitrange,sa,rolebinding'
alias opo='oc get pods -o wide'
alias oev='oc get events --sort-by=.lastTimestamp'
alias oco='oc get co'
alias omcp='oc get mcp'
alias opv='oc get pv,pvc,sc'
EOF

source ~/.bashrc
```

### 2. Bulletproof YAML Editing in Vim (`~/.vimrc`)

YAML forbids tab characters and requires strict 2-space indentation. Configure `~/.vimrc` immediately:

```bash
cat << 'EOF' > ~/.vimrc
set expandtab       " Convert Tab keypresses into spaces
set tabstop=2       " 1 Tab = 2 spaces
set shiftwidth=2    " Indent/unindent with '>>' or '<<' by 2 spaces
set softtabstop=2   " Backspace deletes 2 spaces at once
set autoindent      " Maintain current indentation on new lines
set number          " Show line numbers (critical when oc apply reports an error on line X)
set ruler           " Show line and column number in bottom right
set paste           " Optional: prevents staircase auto-indent when pasting from docs
EOF
```

> 💡 **Vim Multi-Line Indent Trick:** If you paste a block into `vim` and its indentation is off by 2 spaces:
> 1. Press `Esc`, then `Shift + v` (Visual Line mode) and use `j`/`k` arrow keys to highlight the lines.
> 2. Press `>` to shift the entire block right by 2 spaces (or `<` to shift left).
> 3. Press `.` (dot) to repeat the shift as many times as needed!

---

## 🅱️ Step B — The `$do` (`--dry-run=client -o yaml`) Generation Patterns

Never write a Kubernetes/OpenShift resource from scratch. Use `$do` to generate a 100% valid skeleton in 3 seconds, redirect to a `.yaml` file, or pipe straight to `oc apply -f -`.

### 1. Workloads & Networking

```bash
# Deployment
oc create deploy myapp --image=registry.example.com/img:1.0 --replicas=3 --port=8080 $do > deploy.yaml

# Bare Pod
oc run mypod --image=registry.example.com/img:1.0 --port=8080 $do > pod.yaml

# Job & CronJob
oc create job backup --image=registry.example.com/img:1.0 $do -- /bin/sh -c "date" > job.yaml
oc create cronjob nightly --image=registry.example.com/img:1.0 --schedule="0 2 * * *" $do -- /bin/sh -c "date" > cj.yaml

# Services (ClusterIP, NodePort, LoadBalancer)
oc create svc clusterip myapp --tcp=8080:8080 $do > svc.yaml
oc create svc nodeport myapp --tcp=8080:8080 --node-port=30080 $do > nodeport.yaml

# Routes (Standard HTTP, Edge TLS, Passthrough TLS, Re-encrypt TLS)
oc expose svc/myapp --hostname=app.apps.example.com $do > route.yaml
oc create route edge myapp --service=myapp --port=8080 --cert=tls.crt --key=tls.key --hostname=app.apps.example.com $do > edge-route.yaml
oc create route passthrough myapp --service=myapp --port=8443 --hostname=app.apps.example.com $do > pass-route.yaml
oc create route reencrypt myapp --service=myapp --dest-ca-cert=dest.ca --cert=tls.crt --key=tls.key $do > reenc-route.yaml
```

### 2. Config, Security, RBAC & Quotas

```bash
# ConfigMap & Secrets
oc create cm app-cm --from-literal=ENV=prod --from-file=app.conf $do > cm.yaml
oc create secret generic app-sec --from-literal=user=admin --from-literal=pass=secret $do > sec.yaml
oc create secret tls app-tls --cert=server.crt --key=server.key $do > tls-sec.yaml

# ServiceAccount & RBAC
oc create sa app-sa $do > sa.yaml
oc create role pod-reader --verb=get,list,watch --resource=pods $do > role.yaml
oc create rolebinding read-pods --role=pod-reader --user=alice --group=devs --serviceaccount=myproj:app-sa $do > rb.yaml

# ResourceQuota & ClusterResourceQuota
oc create quota proj-quota --hard=pods=10,requests.cpu=2,requests.memory=4Gi,limits.cpu=4,limits.memory=8Gi $do > quota.yaml
oc create clusterquota team-quota --project-annotation-selector=openshift.io/requester=alice --hard=pods=10,secrets=20 $do > crq.yaml
```

---

## 🅲 Step C — Never Hand-Edit YAML When `oc set` & `oc adm` Can Mutate It

Hand-editing deeply nested fields (`volumes:`, `volumeMounts:`, `envFrom:`, `livenessProbe:`, `resources:`) inside `vim` takes 3–5 minutes and is the #1 source of exam typos. Run these 1-line mutations instead!

> 💡 **Want to keep it in a YAML file for GitOps?** Any `oc set` command can mutate a local file without touching the cluster by adding `--local -f deploy.yaml -o yaml > deploy-new.yaml`!

### 1. Injecting & Removing Environment Variables (`oc set env`)

```bash
# Add literal key=value env vars
oc set env deploy/myapp APP_MODE=production PORT=8080

# Import ALL keys from a ConfigMap or Secret
oc set env deploy/myapp --from=configmap/app-cm
oc set env deploy/myapp --from=secret/app-sec --prefix=DB_

# List all current env vars on a Deployment
oc set env deploy/myapp --list

# Remove an env var (note the trailing hyphen '-')
oc set env deploy/myapp APP_MODE-
```

> ⚠️ **Case-Sensitivity Trap with `--prefix`:** If `secret/app-sec` has lowercase key `password` and the exam asks for uppercase env var `DB_PASSWORD`, `--prefix=DB_` will create `DB_password` (wrong case!). When key case changes, use a JSON patch or edit YAML:
> ```bash
> oc patch deploy/myapp --type=json -p='[
>   {"op":"add","path":"/spec/template/spec/containers/0/env/-","value":{"name":"DB_PASSWORD","valueFrom":{"secretKeyRef":{"name":"app-sec","key":"password"}}}}
> ]'
> ```

### 2. Mounting Volumes (`oc set volume`) — Saves 4 Minutes Per Task!

```bash
# Mount a Secret at /etc/certs
oc set volume deploy/myapp --add --name=cert-vol --type=secret --secret-name=app-tls --mount-path=/etc/certs

# Mount a ConfigMap at /etc/config
oc set volume deploy/myapp --add --name=cfg-vol --type=configmap --configmap-name=app-cm --mount-path=/etc/config

# Mount an existing PVC at /var/lib/data
oc set volume deploy/myapp --add --name=data-vol --type=pvc --claim-name=my-pvc --mount-path=/var/lib/data

# Create a NEW PVC on the fly AND mount it in one command!
oc set volume deploy/myapp --add --name=data-vol --type=pvc --claim-name=new-pvc \
  --claim-size=5Gi --claim-mode=ReadWriteOnce --claim-class=gp3-csi --mount-path=/var/lib/data

# Remove a mounted volume
oc set volume deploy/myapp --remove --name=cert-vol
```

### 3. Setting CPU/Memory Requests & Limits (`oc set resources`)

```bash
# Set both requests and limits in 10 seconds
oc set resources deploy/myapp --requests=cpu=100m,memory=128Mi --limits=cpu=500m,memory=512Mi
```

### 4. Configuring Health Probes (`oc set probe`)

```bash
# HTTP GET Readiness Probe on port 8080 path /healthz
oc set probe deploy/myapp --readiness --get-url=http://:8080/healthz --initial-delay-seconds=5 --period-seconds=10

# HTTPS GET Liveness Probe
oc set probe deploy/myapp --liveness --get-url=https://:8443/live --initial-delay-seconds=15

# TCP Socket Probe
oc set probe deploy/myapp --liveness --open-tcp=8080 --initial-delay-seconds=10

# Exec Command Probe
oc set probe deploy/myapp --liveness -- echo ok

# Remove a probe
oc set probe deploy/myapp --liveness --remove
```

### 5. Binding ServiceAccounts & SCCs (`oc set sa` & `oc adm policy`)

```bash
# Attach a ServiceAccount to a Deployment (automatically sets both serviceAccount and serviceAccountName!)
oc set serviceaccount deploy/myapp app-sa

# Grant an SCC (e.g., anyuid or a custom SCC) to a ServiceAccount in the current project (-z)
oc adm policy add-scc-to-user anyuid -z app-sa -n myproj

# Check which SCC a running Pod actually received!
oc get pod <pod-name> -o jsonpath='{.metadata.annotations.openshift\.io/scc}{"\n"}'
```

### 6. Extracting & Updating ConfigMaps/Secrets In-Place (`oc extract` & `oc set data`)

```bash
# Print all decoded Secret keys to stdout (no base64 -d needed!)
oc extract secret/app-sec --to=-

# Extract TLS cert/key files from a Secret into /tmp/certs/
mkdir -p /tmp/certs && oc extract secret/app-tls --to=/tmp/certs --confirm

# Add or update a key inside an existing Secret or ConfigMap (auto-encodes base64 for Secrets!)
oc set data secret/app-sec api_token=supersecret123
oc set data cm/app-cm LOG_LEVEL=debug
```

### 7. Instant Schema Lookup When You Forget a YAML Field (`oc explain`)

Never waste 5 minutes hunting through HTML documentation for a field name when `oc explain` has the entire OpenShift 4.18–4.22 OpenAPI schema offline:

```bash
# Show all fields recursively with their data types
oc explain limitrange.spec.limits
oc explain networkpolicy.spec.ingress
oc explain subscription.spec
oc explain route.spec.tls
```