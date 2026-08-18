# 2.2 — Use ConfigMaps and Secrets to Configure Applications

> **Objective:** Use ConfigMaps and Secrets to configure applications.
> **Exam frequency:** High — usually 1-2 tasks.

## 🎯 Why this matters

Every real app needs config. The CKA tests all 3 ways to inject it: env var, envFrom, volume mount.

## 🧠 ConfigMap vs Secret

| | ConfigMap | Secret |
| --- | --- | --- |
| Stored as | Plain text | base64 (not encryption!) |
| Size limit | 1 MiB | 1 MiB |
| Best for | Non-sensitive config (`LOG_LEVEL`, URLs) | Passwords, tokens, TLS certs |
| Encrypted at rest? | No (cluster default) | No (cluster default — enable EncryptionConfiguration) |

**⚠️ Secrets are NOT encryption.** `base64 -d` reveals the value. Treat them as obfuscation that needs RBAC + EncryptionConfiguration to actually be secure.

## 🛠️ Creating ConfigMaps

### Imperative

```bash
# From literals
k create configmap app-config \
  --from-literal=LOG_LEVEL=info \
  --from-literal=ENV=prod

# From a file (content becomes a single key)
echo 'log_level=info' > app.conf
k create configmap app-config --from-file=app.conf
# → key 'app.conf' with file content as value

# From a file with a custom key
k create configmap app-config --from-file=CONFIG=app.conf
# → key 'CONFIG'

# From a directory
k create configmap app-config --from-file=./configs/
# → one key per file in the directory

# From env-file (.env style: KEY=VALUE per line)
k create configmap app-config --from-env-file=app.env
```

### Declarative

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: default
data:
  LOG_LEVEL: info
  ENV: prod
  app.properties: |
    server.port=8080
    server.host=0.0.0.0
```

## 🛠️ Creating Secrets

### Imperative

```bash
# Generic secret from literals
k create secret generic db-creds \
  --from-literal=username=admin \
  --from-literal=password='S3cur3!'

# From file
k create secret generic tls-secret \
  --from-file=cert.pem \
  --from-file=key.pem

# TLS-type secret (well-known structure)
k create secret tls web-tls --cert=tls.crt --key=tls.key

# Docker registry pull secret
k create secret docker-registry regcred \
  --docker-server=registry.example.com \
  --docker-username=alice \
  --docker-password=hunter2 \
  --docker-email=alice@example.com
```

### Declarative (with base64)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-creds
type: Opaque
data:
  username: YWRtaW4=                # echo -n 'admin' | base64
  password: UzNjdXIzIQ==
```

Or use `stringData` to avoid base64:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-creds
type: Opaque
stringData:
  username: admin
  password: S3cur3!
```

Common Secret types:
- `Opaque` — generic (default)
- `kubernetes.io/tls` — for TLS (must have keys `tls.crt`, `tls.key`)
- `kubernetes.io/dockerconfigjson` — image pull secret
- `kubernetes.io/service-account-token` — SA token

## 💉 Consuming in Pods — 3 patterns

### Pattern 1 — Single env var from one key

```yaml
spec:
  containers:
  - name: app
    image: myapp
    env:
    - name: LOG_LEVEL
      valueFrom:
        configMapKeyRef:
          name: app-config
          key: LOG_LEVEL
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: db-creds
          key: password
```

### Pattern 2 — All keys as env vars (envFrom)

```yaml
spec:
  containers:
  - name: app
    image: myapp
    envFrom:
    - configMapRef:
        name: app-config
    - secretRef:
        name: db-creds
    # Add prefix if you want:
    # - configMapRef:
    #     name: app-config
    #   prefix: APP_
```

### Pattern 3 — Mount as files in a volume

```yaml
spec:
  containers:
  - name: app
    image: myapp
    volumeMounts:
    - name: config
      mountPath: /etc/app/
      readOnly: true
    - name: secrets
      mountPath: /etc/secrets/
      readOnly: true
  volumes:
  - name: config
    configMap:
      name: app-config              # each key becomes a file in /etc/app/
  - name: secrets
    secret:
      secretName: db-creds
      defaultMode: 0400             # restrict file perms (optional)
```

You can also mount **specific keys** to specific paths:

```yaml
  volumes:
  - name: config
    configMap:
      name: app-config
      items:
      - key: app.properties
        path: application.properties
        mode: 0644
```

This mounts only the `app.properties` key as the file `application.properties`.

## 🔄 What happens when you update a ConfigMap/Secret?

- **Env vars**: NOT updated. Pods need to be restarted (`k rollout restart deployment/X`).
- **Volume mounts**: Updated within ~1 minute (depending on `subPath` — subPath does NOT auto-update).

This is why teams trigger rollouts on config changes (or use checksums in pod annotations, or `kustomize` configMapGenerator which appends a hash).

## 🏋️ Exam-style exercises

### Exercise 1
Create a ConfigMap `app-config` in namespace `app` with two keys: `LOG_LEVEL=debug`, `MAX_CONN=100`. Then create a Pod `myapp` running `nginx` that has both as environment variables.

<details><summary>Solution</summary>

```bash
k create namespace app
k create cm app-config --from-literal=LOG_LEVEL=debug --from-literal=MAX_CONN=100 -n app

k run myapp --image=nginx -n app $do > myapp.yaml
```

Edit `myapp.yaml`:
```yaml
spec:
  containers:
  - name: myapp
    image: nginx
    envFrom:
    - configMapRef:
        name: app-config
```

```bash
k apply -f myapp.yaml
k exec -n app myapp -- env | grep -E 'LOG_LEVEL|MAX_CONN'
```
</details>

### Exercise 2
A pod needs the file `/etc/app/config.json` to be the contents of `app-config-2` ConfigMap key `config`. Create the ConfigMap from a file and mount it.

<details><summary>Solution</summary>

```bash
cat > config.json <<EOF
{"endpoint": "https://api.example.com"}
EOF

k create cm app-config-2 --from-file=config=config.json -n app

# Pod
cat <<EOF | k apply -n app -f -
apiVersion: v1
kind: Pod
metadata:
  name: cfgpod
spec:
  containers:
  - name: app
    image: nginx
    volumeMounts:
    - name: cfg
      mountPath: /etc/app
  volumes:
  - name: cfg
    configMap:
      name: app-config-2
      items:
      - key: config
        path: config.json
EOF

k exec -n app cfgpod -- cat /etc/app/config.json
```
</details>

### Exercise 3
Create a Secret containing a TLS cert and key (you can use any cert files in `/root/`). Then mount it at `/etc/tls/` in a Pod.

<details><summary>Solution</summary>

```bash
k create secret tls web-tls --cert=/root/tls.crt --key=/root/tls.key -n app

cat <<EOF | k apply -n app -f -
apiVersion: v1
kind: Pod
metadata:
  name: tlspod
spec:
  containers:
  - name: web
    image: nginx
    volumeMounts:
    - name: tls
      mountPath: /etc/tls
      readOnly: true
  volumes:
  - name: tls
    secret:
      secretName: web-tls
EOF

k exec -n app tlspod -- ls /etc/tls
# tls.crt  tls.key
```
</details>

### Exercise 4
A Deployment `api` reads `MAX_CONN` from a ConfigMap. You updated the ConfigMap but pods still show the old value. Trigger a rollout.

<details><summary>Solution</summary>

```bash
k rollout restart deployment/api -n app
k rollout status deployment/api -n app
```
</details>

## ⚠️ Common pitfalls

- **Using `data:` for non-base64 in a Secret** → `kubectl apply` will error. Use `stringData:` instead, or base64-encode.
- **Forgetting `-n <ns>`** when creating — ends up in `default`.
- **Updating ConfigMap and expecting env vars to update** — they don't. Need a rollout.
- **`base64` adds newlines by default.** Use `echo -n 'value' | base64` (the `-n` matters), or `printf 'value' | base64`.
- **Wrong key name in `valueFrom`** — pod fails to start with `CreateContainerConfigError`. Check key spelling.
- **Mounting ConfigMap onto an existing directory** — replaces it entirely. Use `subPath` to mount a single file without hiding the directory.

## 📚 Doc bookmarks

- [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
- [Configure a Pod to Use a ConfigMap](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/)
