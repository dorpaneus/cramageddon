<div align="center">

[⬅️ Prev: Authentication & authorization](./04-auth-and-authorization.md) &nbsp;·&nbsp; [🏠 Home](../README.md) &nbsp;·&nbsp; [Next: Expose non-HTTP/SNI applications ➡️](./06-expose-non-http-sni.md)

</div>

# Objective 5 — Configure Network Security

> **Exam study points:**
> - Configure networking components
> - Troubleshoot software-defined networking
> - Create and edit external routes
> - Control cluster network ingress
> - Secure external and internal traffic using TLS certificates
> - Configure application network policies

OCP 4.18 uses **OVN-Kubernetes** as the only supported CNI (OpenShift SDN was removed in 4.17). Day-to-day, you mostly interact with Routes and NetworkPolicies; OVN is transparent.

---

## §1 — The networking stack

```
[external client]
      │  https://hello.apps.example.com
      ▼
[Wildcard DNS *.apps.example.com → IngressController(s)]
      │
      ▼
[openshift-ingress: HAProxy router pods]   ← handles Routes
      │
      ▼
[Service (ClusterIP) hello]                ← stable VIP + DNS hello.myapp.svc
      │
      ▼
[Pods matching service.selector]
```

`oc -n openshift-ingress get pods` shows the routers.
`oc get ingresscontroller -n openshift-ingress-operator default -o yaml` controls them.

## §2 — Routes (recap from Obj 3) and route YAML

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: hello
spec:
  host: hello.apps.example.com
  to:
    kind: Service
    name: hello
  port:
    targetPort: 8080
```

Useful imperative ops:

```bash
oc expose svc/hello                                  # HTTP route, auto-hostname
oc expose svc/hello --hostname=hello.example.com
oc get routes
oc get route hello -o jsonpath='{.spec.host}'

# Edit hostname / target port / TLS in place
oc edit route hello
oc patch route hello -p '{"spec":{"host":"newhost.apps.example.com"}}'
```

## §3 — TLS-terminated routes (three flavors)

| Mode | Where TLS terminates | When to use |
|------|----------------------|-------------|
| `edge` | Router decrypts. Pod sees plain HTTP. | Most common; pod doesn't need its own cert. |
| `passthrough` | Router does not terminate; raw TLS to pod. | Pod needs to see the original cert (mTLS, custom protocols). |
| `reencrypt` | Router decrypts with one cert, re-encrypts to pod with another. | Defence-in-depth; pod also serves TLS but with a different cert. |

### Edge route

```bash
oc create route edge hello --service=hello \
  --hostname=hello.apps.example.com \
  --cert=server.crt --key=server.key \
  --ca-cert=ca.crt                                   # optional intermediate

# Force HTTPS-only (redirect HTTP → HTTPS)
oc patch route hello -p '{"spec":{"tls":{"insecureEdgeTerminationPolicy":"Redirect"}}}'
```

### Passthrough

```bash
# Pod must serve TLS on its own. The Service must target the TLS port.
oc create route passthrough hello --service=hello-tls \
  --hostname=hello.apps.example.com
```

### Re-encrypt

```bash
oc create route reencrypt hello --service=hello-tls \
  --hostname=hello.apps.example.com \
  --cert=server.crt --key=server.key --ca-cert=ca.crt \
  --dest-ca-cert=pod-ca.crt
```

### Full YAML examples

```yaml
# edge
apiVersion: route.openshift.io/v1
kind: Route
metadata: { name: hello }
spec:
  host: hello.apps.example.com
  to: { kind: Service, name: hello }
  port: { targetPort: 8080 }
  tls:
    termination: edge
    key:  |
      -----BEGIN PRIVATE KEY-----
      …
    certificate: |
      -----BEGIN CERTIFICATE-----
      …
    caCertificate: |
      -----BEGIN CERTIFICATE-----
      …
    insecureEdgeTerminationPolicy: Redirect
---
# passthrough
spec:
  tls:
    termination: passthrough
---
# reencrypt
spec:
  tls:
    termination: reencrypt
    key: |
      …
    certificate: |
      …
    caCertificate: |
      …
    destinationCACertificate: |
      …
```

### Generating self-signed certs for practice

```bash
# CA
openssl genrsa -out ca.key 2048
openssl req -x509 -new -nodes -key ca.key -subj "/CN=demo-ca" -days 365 -out ca.crt

# Server cert signed by the CA, valid for the route hostname
openssl genrsa -out server.key 2048
openssl req -new -key server.key -subj "/CN=hello.apps.example.com" -out server.csr
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -days 365 -out server.crt
```

## §4 — NetworkPolicy

`NetworkPolicy` is the namespace-scoped Kubernetes way to firewall pod-to-pod traffic. OVN-Kubernetes enforces it.

**Default OCP behavior in a project**: an implicit "allow all ingress from the cluster network" — until you create the first NetworkPolicy in the namespace. Once you do, **deny by default** kicks in for pods matching that policy's selector.

### The classic starter set

```yaml
# 1. Deny all ingress in this namespace by default
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-ingress
  namespace: myapp
spec:
  podSelector: {}
  policyTypes: [Ingress]
---
# 2. Allow traffic from inside the same namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-ns
  namespace: myapp
spec:
  podSelector: {}
  policyTypes: [Ingress]
  ingress:
    - from:
        - podSelector: {}
---
# 3. Allow OpenShift router (Ingress) to reach my pods on port 8080
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-router
  namespace: myapp
spec:
  podSelector:
    matchLabels:
      app: hello
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              policy-group.network.openshift.io/ingress: ""
      ports:
        - protocol: TCP
          port: 8080
```

> **Which label?** The docs' preferred selector for OVN-Kubernetes is `policy-group.network.openshift.io/ingress: ""`. The `openshift-ingress` namespace also carries the older `network.openshift.io/policy-group: ingress`, so policies using either still match — but use the documented one. Check with `oc get ns openshift-ingress --show-labels`.
>
> **HostNetwork routers (CRC, SNO, many bare-metal clusters):** if the IngressController publishes with `HostNetwork`, router traffic comes from the **host network**, not from `openshift-ingress`, and the policy above won't match it. Add a second `from` entry:
>
> ```yaml
>     - from:
>         - namespaceSelector:
>             matchLabels:
>               policy-group.network.openshift.io/host-network: ""
> ```
>
> Find out which case you're in: `oc get ingresscontroller default -n openshift-ingress-operator -o jsonpath='{.status.endpointPublishingStrategy.type}{"\n"}'` (`HostNetwork` vs `LoadBalancerService`).

### Allow from a specific other namespace + specific pod

```yaml
spec:
  podSelector:
    matchLabels: {app: hello}
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels: {kubernetes.io/metadata.name: frontend}
          podSelector:
            matchLabels: {role: client}
      ports:
        - {protocol: TCP, port: 8080}
```

### Egress example (let only DNS + specific external IP out)

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: restrict-egress
  namespace: myapp
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
    - to:
        - namespaceSelector:
            matchLabels: {kubernetes.io/metadata.name: openshift-dns}
      ports:
        - {protocol: UDP, port: 5353}   # the DNS pods listen on 5353; the Service maps 53 → 5353,
        - {protocol: TCP, port: 5353}   # and policy is matched on the pod's port, so 53 alone would block DNS
    - to:
        - ipBlock: {cidr: 10.0.0.5/32}
      ports:
        - {protocol: TCP, port: 5432}
```

### Test from inside

```bash
oc run probe --rm -it --restart=Never \
  --image=registry.access.redhat.com/ubi9/ubi-minimal -n myapp -- \
  curl -m 3 -s http://hello:8080 || echo BLOCKED
```

## §5 — Cluster ingress (the IngressController object)

You won't typically build your own IngressController on EX280, but know it exists and how to inspect it.

```bash
oc get ingresscontroller -n openshift-ingress-operator
oc describe ingresscontroller default -n openshift-ingress-operator

# Default route subdomain (e.g. apps.example.com)
oc get ingresses.config cluster -o jsonpath='{.spec.domain}'

# Custom IngressController on a separate domain (advanced)
```

To add a **custom default certificate** for `*.apps.example.com`:

```bash
oc create secret tls custom-router-cert \
  --cert=wildcard.crt --key=wildcard.key \
  -n openshift-ingress

oc patch ingresscontroller default -n openshift-ingress-operator \
  --type=merge \
  -p '{"spec":{"defaultCertificate":{"name":"custom-router-cert"}}}'
```

## §5b — Internal TLS: service serving certificates

Routes cover **external** TLS. For TLS **inside** the cluster (pod → Service), OpenShift's `service-ca` operator can issue certificates for you, signed by a cluster-internal CA, and keep them rotated.

**1. Ask for a serving certificate** — annotate the Service with the name of the Secret you want:

```bash
oc annotate service secure \
  service.beta.openshift.io/serving-cert-secret-name=secure-tls
```

The operator creates Secret `secure-tls` (type `kubernetes.io/tls`, keys `tls.crt` / `tls.key`) for the DNS names `secure.<namespace>.svc` and `secure.<namespace>.svc.cluster.local`. Mount it into the pod and point the server at it.

**2. Give clients the CA** — annotate a ConfigMap and the operator injects the CA bundle under the key `service-ca.crt`:

```bash
oc create configmap service-ca
oc annotate configmap service-ca service.beta.openshift.io/inject-cabundle=true
oc get configmap service-ca -o jsonpath='{.data.service-ca\.crt}' | head -2
# -----BEGIN CERTIFICATE-----
```

Clients mount that ConfigMap and verify the server with it (e.g. `curl --cacert /etc/ca/service-ca.crt https://secure.<ns>.svc:8443`).

**3. Re-encrypt routes get simpler** — when the backend uses a service serving certificate, a `reencrypt` route doesn't need `--dest-ca-cert`: the router already trusts the service CA.

```bash
oc create route reencrypt secure --service=secure --port=8443
```

| Annotation | On | Result |
|------------|----|--------|
| `service.beta.openshift.io/serving-cert-secret-name: <secret>` | Service | TLS Secret for `<svc>.<ns>.svc` |
| `service.beta.openshift.io/inject-cabundle: "true"` | ConfigMap | Key `service-ca.crt` with the service CA |

## §6 — Troubleshooting SDN issues

```bash
# Is the network operator healthy?
oc get co network

# All netpol in a namespace
oc get networkpolicy -n myapp

# Can pod A reach pod B?
oc rsh -n myapp <pod-a>
> curl -m 3 -sv http://<podB-IP>:8080

# DNS resolving?
oc rsh -n myapp <pod>
> getent hosts hello
> getent hosts hello.myapp.svc

# Route reachable externally?
curl -ksvI https://hello.apps.example.com

# Ingress router logs (when a route 503s)
oc logs -n openshift-ingress deploy/router-default | tail
```

---

## 🧪 Labs

### Lab 5.1 — Edge route with TLS + HTTP redirect (25 min)

Edge termination is the most common Route type on the exam: TLS ends at the router, plaintext to the pod, with an option to force HTTP→HTTPS. This lab builds one with a custom cert and a redirect.

**Prerequisites:**
- Project: `oc new-project lab51`.
- `openssl` installed.
- Know your cluster's apps domain: `oc get ingresses.config/cluster -o jsonpath='{.spec.domain}{"\n"}'` (e.g. `apps.crc.testing` or `apps.<cluster>.example.com`).

---

#### Step 1 — Deploy `hello-openshift`

<details>
<summary>💡 Solution</summary>

```bash
oc project lab51
oc create deployment hello \
  --image=quay.io/openshifttest/hello-openshift:1.2.0
oc expose deployment hello --port=8080          # creates a ClusterIP Service

oc get svc hello
# NAME    TYPE        CLUSTER-IP     PORT(S)
# hello   ClusterIP   172.30.x.x     8080/TCP

oc get pods -l app=hello
# hello-xxxxx   1/1   Running
```

The `hello-openshift` image serves plain HTTP on 8080 (and 8888). We'll put TLS in front of it at the router.

</details>

---

#### Step 2 — Generate a self-signed cert for the route hostname

<details>
<summary>💡 Solution</summary>

```bash
# Set your hostname (adjust domain to your cluster)
DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
HOST=hello.$DOMAIN
echo $HOST
# hello.apps.crc.testing   (or similar)

# Generate a self-signed cert + key in one command
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout tls.key -out tls.crt \
  -subj "/CN=$HOST" \
  -addext "subjectAltName=DNS:$HOST"

ls -l tls.crt tls.key
```

**Flag breakdown:**
- `-x509` — output a self-signed cert (not a CSR).
- `-newkey rsa:2048` — generate a new 2048-bit RSA key.
- `-nodes` — "no DES", i.e. don't encrypt the private key with a passphrase (routers can't type passwords).
- `-subj "/CN=$HOST"` — set the Common Name to the route hostname.
- `-addext "subjectAltName=DNS:$HOST"` — modern TLS clients require a SAN; CN alone is deprecated.

**Gotcha:** the cert's CN/SAN must match the Route's hostname exactly, or `curl` (without `-k`) will reject it. Since it's self-signed we'll use `-k` anyway, but matching the hostname is still correct practice.

</details>

---

#### Step 3 — Create an edge Route with `--cert/--key`

<details>
<summary>💡 Solution</summary>

```bash
oc create route edge hello \
  --service=hello \
  --hostname=$HOST \
  --cert=tls.crt \
  --key=tls.key
# route.route.openshift.io/hello created
```

**On the `--ca-cert` flag:** for a self-signed cert there's no separate CA, so you can omit `--ca-cert`. If your leaf cert were signed by an intermediate/root CA, you'd pass `--ca-cert=ca.crt` so the router can serve the full chain.

**Declarative equivalent** (useful to know for the exam):

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: hello
  namespace: lab51
spec:
  host: hello.apps.crc.testing
  to:
    kind: Service
    name: hello
  port:
    targetPort: 8080
  tls:
    termination: edge
    certificate: |
      -----BEGIN CERTIFICATE-----
      ...tls.crt contents...
      -----END CERTIFICATE-----
    key: |
      -----BEGIN PRIVATE KEY-----
      ...tls.key contents...
      -----END PRIVATE KEY-----
```

**Cert-less edge route:** if you omit `--cert/--key`, the router serves its own default wildcard cert. That's fine for many exam tasks ("create an edge route" without specifying a cert). Use a custom cert only when the task supplies or requires one.

</details>

---

#### Step 4 — Set `insecureEdgeTerminationPolicy: Redirect`

<details>
<summary>💡 Solution</summary>

**At creation time** (cleaner — add the flag to Step 3):

```bash
oc create route edge hello \
  --service=hello --hostname=$HOST \
  --cert=tls.crt --key=tls.key \
  --insecure-policy=Redirect
```

**Or patch an existing route:**

```bash
oc patch route hello --type=merge \
  -p '{"spec":{"tls":{"insecureEdgeTerminationPolicy":"Redirect"}}}'
```

**The three `insecureEdgeTerminationPolicy` values:**

| Value | HTTP (port 80) behavior |
|-------|-------------------------|
| `None` (default) | Plain HTTP is **not served** for this route (the router answers 503) — only HTTPS works |
| `Redirect` | HTTP requests get a 301/302 redirect to HTTPS |
| `Allow` | Plain HTTP is served alongside HTTPS (not recommended) |

`Redirect` is what "force users onto HTTPS" means.

**Verify the route config:**

```bash
oc get route hello -o jsonpath='{.spec.tls.termination}{"\t"}{.spec.tls.insecureEdgeTerminationPolicy}{"\n"}'
# edge   Redirect
```

</details>

---

#### Step 5 — `curl` HTTP, confirm redirect to HTTPS

<details>
<summary>💡 Solution</summary>

```bash
curl -kI http://$HOST
# HTTP/1.1 302 Found                        (or 301)
# Location: https://hello.apps.crc.testing/
# ...
```

The `-I` fetches headers only; `-k` ignores the self-signed cert warning. A `302`/`301` with a `Location:` header pointing to `https://` confirms the redirect policy is working.

**If you get `503 Service Unavailable` (the router's "Application is not available" page) on HTTP:** the `insecureEdgeTerminationPolicy` is probably `None` (the default) — the router still listens on port 80 but serves nothing for this host over plain HTTP. Re-check Step 4.

</details>

---

#### Step 6 — `curl` HTTPS, confirm 200

<details>
<summary>💡 Solution</summary>

```bash
curl -kI https://$HOST
# HTTP/1.1 200 OK
# ...

# Full body:
curl -k https://$HOST
# Hello OpenShift!

# Inspect the cert the router is serving (should be YOUR self-signed cert):
openssl s_client -connect $HOST:443 -servername $HOST </dev/null 2>/dev/null \
  | openssl x509 -noout -subject
# subject=CN=hello.apps.crc.testing
```

That `subject=CN=hello.apps.crc.testing` confirms the router is presenting the custom cert you supplied, not its default wildcard.

**Full verification checklist:**

```bash
oc get route hello -o jsonpath='{.spec.tls.termination}'                        # edge
oc get route hello -o jsonpath='{.spec.tls.insecureEdgeTerminationPolicy}'      # Redirect
curl -kI http://$HOST  | head -1                                               # 30x
curl -kI https://$HOST | head -1                                               # 200
```

**Cleanup:**

```bash
oc delete project lab51
```

</details>

---

### Lab 5.2 — Passthrough route (25 min)

With passthrough, the router does NOT terminate TLS — encrypted traffic flows straight to the pod, which presents its own certificate. This lab proves the pod's cert (not the router's) is what the client sees.

**Prerequisites:**
- Project: `oc new-project lab52`.
- `openssl` installed.

---

#### Step 1 — Deploy an app that serves TLS on port 8443

The simplest reliable option is an nginx configured with a self-signed cert stored in a Secret. `hello-openshift` doesn't serve TLS, so we build a tiny TLS nginx.

<details>
<summary>💡 Solution</summary>

```bash
DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
HOST=secure.$DOMAIN

# 1. Generate the pod's own cert (CN = the route hostname)
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout pod-tls.key -out pod-tls.crt \
  -subj "/CN=$HOST" -addext "subjectAltName=DNS:$HOST"

# 2. Store the cert in a Secret (tls type)
oc create secret tls pod-cert --cert=pod-tls.crt --key=pod-tls.key -n lab52

# 3. Provide an nginx config that listens on 8443 with TLS
cat > nginx-ssl.conf <<'EOF'
server {
    listen 8443 ssl;
    ssl_certificate     /etc/nginx/tls/tls.crt;
    ssl_certificate_key /etc/nginx/tls/tls.key;
    location / { return 200 "secure hello from the pod\n"; }
}
EOF
oc create configmap nginx-ssl-conf --from-file=default.conf=nginx-ssl.conf -n lab52

# 4. Deploy nginx mounting both
cat <<EOF | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: secure
  namespace: lab52
spec:
  replicas: 1
  selector: {matchLabels: {app: secure}}
  template:
    metadata: {labels: {app: secure}}
    spec:
      containers:
      - name: nginx
        image: registry.access.redhat.com/ubi9/nginx-124:latest
        command: ["nginx","-g","daemon off;"]
        ports:
        - {containerPort: 8443}
        volumeMounts:
        - {name: tls, mountPath: /etc/nginx/tls, readOnly: true}
        - {name: conf, mountPath: /opt/app-root/etc/nginx.d, readOnly: true}   # UBI nginx loads extra server blocks from here, not /etc/nginx/conf.d
      volumes:
      - {name: tls, secret: {secretName: pod-cert}}
      - {name: conf, configMap: {name: nginx-ssl-conf}}
EOF

oc rollout status deployment/secure -n lab52
```

**Simpler alternative if the nginx config fussiness isn't worth it:** use any prebuilt TLS-serving image (e.g. `quay.io/openshift-examples/nginx-ssl` if available in your environment). The key requirement is: **the pod terminates TLS on a known port**.

</details>

---

#### Step 2 — Create a Service on port 8443

<details>
<summary>💡 Solution</summary>

```bash
oc expose deployment secure --port=8443 --target-port=8443 -n lab52
# service/secure created

oc get svc secure -n lab52
# NAME     TYPE        CLUSTER-IP    PORT(S)
# secure   ClusterIP   172.30.x.x    8443/TCP

# Confirm endpoints are populated (pod is behind the service)
oc get endpointslices -n lab52 -l kubernetes.io/service-name=secure
# NAME           ADDRESSTYPE   PORTS   ENDPOINTS
# secure-xxxxx   IPv4          8443    10.x.x.x
```

</details>

---

#### Step 3 — Create a passthrough Route

<details>
<summary>💡 Solution</summary>

```bash
oc create route passthrough secure \
  --service=secure \
  --hostname=$HOST \
  --port=8443
# route.route.openshift.io/secure created
```

**Declarative form:**

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: secure
  namespace: lab52
spec:
  host: secure.apps.crc.testing
  to:
    kind: Service
    name: secure
  port:
    targetPort: 8443
  tls:
    termination: passthrough
```

**Key difference from edge:** a passthrough Route has **no** `certificate`/`key` fields. The router isn't terminating TLS, so it doesn't need a cert — it just forwards the encrypted stream to the pod based on SNI (Server Name Indication) in the TLS handshake.

**Why passthrough requires SNI:** since the router can't read the (encrypted) HTTP Host header, it routes based on the hostname in the TLS SNI extension. This is why passthrough works for HTTPS but is also the mechanism behind exposing non-HTTP TLS services (covered in Objective 6).

</details>

---

#### Step 4 — Verify the cert returned externally is the POD's cert

<details>
<summary>💡 Solution</summary>

```bash
# Fetch the cert presented at the route and check its subject
openssl s_client -connect $HOST:443 -servername $HOST </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer
# subject=CN=secure.apps.crc.testing
# issuer=CN=secure.apps.crc.testing    ← self-signed by us = the POD's cert
```

**Contrast with edge:** if this were an edge route, the subject/issuer would be the **router's** default wildcard cert (something like `CN=*.apps.<cluster>` issued by the ingress operator's CA). Seeing your own `CN=secure.apps.crc.testing` proves TLS was **not** terminated at the router — it passed through to the pod.

**Functional test:**

```bash
curl -k https://$HOST
# secure hello from the pod
```

**Side-by-side summary of the three terminations:**

| Termination | Who holds the cert | Router decrypts? | Pod needs TLS? |
|-------------|--------------------|--------------------|----------------|
| `edge` | Router (cert on the Route) | Yes | No (plain HTTP) |
| `passthrough` | Pod | No | **Yes** |
| `reencrypt` | Router (edge) + Pod (re-encrypt leg) | Yes, then re-encrypts | **Yes** |

**Cleanup:**

```bash
oc delete project lab52
```

</details>

---

### Lab 5.3 — NetworkPolicy fortress (30 min)

NetworkPolicies are default-allow until the first policy selects a pod, then default-deny for that pod. This lab builds up a layered policy set from wide-open to tightly-scoped.

**Prerequisites:**
- Cluster-admin.
- Two projects: `oc new-project lab53` and `oc new-project frontend`.

---

#### Step 1 — Deploy `hello` (Deployment + Service + Route) in `lab53`

<details>
<summary>💡 Solution</summary>

```bash
oc project lab53
oc create deployment hello \
  --image=quay.io/openshifttest/hello-openshift:1.2.0
oc expose deployment hello --port=8080
oc expose service hello                       # Route

oc get deploy,svc,route -n lab53
```

</details>

---

#### Step 2 — Confirm a pod in another namespace can reach `hello` (baseline: wide open)

<details>
<summary>💡 Solution</summary>

```bash
# Run a throwaway client pod in the 'frontend' namespace and curl the service in lab53
oc run probe --image=registry.access.redhat.com/ubi9/ubi-minimal:latest \
  -n frontend --rm -it --restart=Never -- \
  curl -m 5 -s http://hello.lab53.svc.cluster.local:8080
# Hello OpenShift!
```

**Why it works with no policy:** OVN-Kubernetes (the only CNI in 4.18) is default-allow. Until a NetworkPolicy selects a pod, all ingress is permitted — including cross-namespace. The FQDN `hello.lab53.svc.cluster.local` is the in-cluster service DNS name.

</details>

---

#### Step 3 — Apply `deny-all-ingress`; test again (should fail)

<details>
<summary>💡 Solution</summary>

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-ingress
  namespace: lab53
spec:
  podSelector: {}          # empty = ALL pods in lab53
  policyTypes:
  - Ingress
  # no ingress rules = deny all ingress
```

```bash
oc apply -f deny-all.yaml -n lab53

# Same probe as Step 2 — now it hangs and times out
oc run probe --image=registry.access.redhat.com/ubi9/ubi-minimal:latest \
  -n frontend --rm -it --restart=Never -- \
  curl -m 5 -s http://hello.lab53.svc.cluster.local:8080
# (no output; command exits ~5s later with timeout)
```

**The rule:** the moment ANY NetworkPolicy selects a pod (here `podSelector: {}` selects all), that pod switches to default-deny for the listed `policyTypes`. With no `ingress:` rules, nothing is allowed in.

**External Route also breaks now:**

```bash
curl -m 5 -I http://$(oc get route hello -n lab53 -o jsonpath='{.spec.host}')
# times out — the router itself is now blocked from reaching the pod
```

</details>

---

#### Step 4 — Add `allow-from-router`; external Route works again

<details>
<summary>💡 Solution</summary>

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-router
  namespace: lab53
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          policy-group.network.openshift.io/ingress: ""
    - namespaceSelector:                       # only needed when the router uses HostNetwork
        matchLabels:                           # (CRC, SNO, many bare-metal clusters) — harmless otherwise
          policy-group.network.openshift.io/host-network: ""
```

```bash
oc apply -f allow-router.yaml -n lab53

# The ingress operator labels the router namespace itself; just verify (don't relabel system namespaces):
oc get ns openshift-ingress --show-labels | tr ',' '\n' | grep policy-group
# policy-group.network.openshift.io/ingress=
# network.openshift.io/policy-group=ingress

# Which publishing strategy does the router use?
oc get ingresscontroller default -n openshift-ingress-operator \
  -o jsonpath='{.status.endpointPublishingStrategy.type}{"\n"}'

# External route now works:
curl -m 5 -I http://$(oc get route hello -n lab53 -o jsonpath='{.spec.host}')
# HTTP/1.1 200 OK
```

**Why these labels:** `policy-group.network.openshift.io/ingress: ""` is the selector the docs prescribe for "allow the router in" on OVN-Kubernetes. When the router runs on the host network (`HostNetwork` strategy), its traffic doesn't come from `openshift-ingress` at all, so you also allow `policy-group.network.openshift.io/host-network: ""`. The two list items are separate `-` entries — **OR** — so either source is allowed. (The cross-namespace probe from `frontend` is still blocked — we only allowed the router.)

</details>

---

#### Step 5 — Add `allow-same-ns`; pods inside `lab53` can reach `hello`

<details>
<summary>💡 Solution</summary>

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
  namespace: lab53
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector: {}        # any pod IN THIS namespace
```

```bash
oc apply -f allow-same-ns.yaml -n lab53

# A probe INSIDE lab53 can now reach hello:
oc run probe --image=registry.access.redhat.com/ubi9/ubi-minimal:latest \
  -n lab53 --rm -it --restart=Never -- \
  curl -m 5 -s http://hello.lab53.svc.cluster.local:8080
# Hello OpenShift!
```

**Key distinction:** a bare `podSelector: {}` inside an `ingress.from` block means "any pod in the **same** namespace as the policy". To allow another namespace you need a `namespaceSelector`. NetworkPolicies are namespace-scoped — the `from` selectors are interpreted relative to the policy's namespace unless a `namespaceSelector` widens them.

</details>

---

#### Step 6 — Allow ONLY `role=client` pods in namespace `frontend` to reach `hello` on 8080

<details>
<summary>💡 Solution</summary>

This needs a combined `namespaceSelector` + `podSelector` in a single `from` entry (AND semantics), plus a `ports` restriction.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-client
  namespace: lab53
spec:
  podSelector:
    matchLabels:
      app: hello
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: frontend
      podSelector:
        matchLabels:
          role: client
    ports:
    - protocol: TCP
      port: 8080
```

```bash
oc apply -f allow-frontend-client.yaml -n lab53
```

**Critical AND vs OR gotcha** — the two selectors are inside a **single** `from` array element (no `-` separating them), which means **AND**: "a pod that is in namespace `frontend` AND has label `role=client`". If you had written them as two separate list items:

```yaml
  ingress:
  - from:
    - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: frontend}}
    - podSelector: {matchLabels: {role: client}}    # ← separate '-' = OR
```

…that would mean "any pod in `frontend` **OR** any pod anywhere labeled `role=client`" — much wider. Indentation here changes the security posture. Watch it closely.

**The `kubernetes.io/metadata.name` label** is auto-applied to every namespace by Kubernetes, so it's the reliable way to select a namespace by name without manually labeling it.

**Verify — matching pod is allowed:**

```bash
# Label a client pod correctly and test
oc run client --image=registry.access.redhat.com/ubi9/ubi-minimal:latest \
  -n frontend --labels=role=client --rm -it --restart=Never -- \
  curl -m 5 -s http://hello.lab53.svc.cluster.local:8080
# Hello OpenShift!   ← allowed (right ns + right label)
```

**Verify — non-matching pod is blocked:**

```bash
# Same namespace, WRONG label
oc run notclient --image=registry.access.redhat.com/ubi9/ubi-minimal:latest \
  -n frontend --labels=role=other --rm -it --restart=Never -- \
  curl -m 5 -s http://hello.lab53.svc.cluster.local:8080
# (times out — label doesn't match)
```

**Cleanup:**

```bash
oc delete project lab53 frontend
```

</details>

---

### Lab 5.4 — Troubleshoot a 503 (20 min)

A 503 on a Route almost always means "the router can't reach a healthy backend pod." This lab teaches the top-down path-walk that isolates the break — a guaranteed exam skill.

**Prerequisites:**
- Project: `oc new-project lab54`.

---

#### Step 1 — Set up a working baseline, then break it (pick one fault)

<details>
<summary>💡 Solution</summary>

**Working baseline:**

```bash
oc project lab54
oc create deployment hello --image=quay.io/openshifttest/hello-openshift:1.2.0
oc expose deployment hello --port=8080
oc expose service hello
ROUTE=$(oc get route hello -o jsonpath='{.spec.host}')
curl -sI http://$ROUTE | head -1
# HTTP/1.1 200 OK   ← baseline good
```

**Now introduce ONE of these faults (have a peer pick, or pick blind):**

```bash
# Fault A — Route points at a non-existent service
oc patch route hello --type=merge -p '{"spec":{"to":{"name":"wrong-svc"}}}'

# Fault B — Route targets a port the pod doesn't serve
oc patch route hello --type=merge -p '{"spec":{"port":{"targetPort":9999}}}'

# Fault C — Service selector doesn't match the pods
oc patch service hello --type=merge -p '{"spec":{"selector":{"app":"nope"}}}'

# Fault D — No running pods
oc scale deployment hello --replicas=0
```

Then re-test:

```bash
curl -sI http://$ROUTE | head -1
# HTTP/1.1 503 Service Unavailable
```

</details>

---

#### Step 2 — Walk the path top-down and identify the break

<details>
<summary>💡 Solution</summary>

Diagnose in this order — **Route → Service → Endpoints → Pods**. The break is wherever the chain first goes empty/wrong.

```bash
# 1. ROUTE — where does it point, and on what port?
oc get route hello -o jsonpath='to.name={.spec.to.name}{"\t"}targetPort={.spec.port.targetPort}{"\n"}'
# to.name=hello   targetPort=8080     ← if to.name is 'wrong-svc' → Fault A
#                                        if targetPort is 9999    → Fault B

# 2. SERVICE — does the named service exist? what's its selector?
oc get svc hello
# If "NotFound" and the route pointed elsewhere → confirms Fault A
oc get svc hello -o jsonpath='selector={.spec.selector}{"\n"}'
# selector={"app":"hello"}    ← if {"app":"nope"} → Fault C

# 3. ENDPOINTS — THE key diagnostic. Empty endpoints = service matches no ready pods.
oc get endpointslices -l kubernetes.io/service-name=hello
# NAME          ADDRESSTYPE   PORTS     ENDPOINTS
# hello-xxxxx   IPv4          8080      10.x.x.x     ← healthy
# hello-xxxxx   IPv4          <unset>   <unset>      ← BROKEN: selector mismatch (C) or no pods (D)
# (oc describe svc hello shows the same on its "Endpoints:" line;
#  oc get endpoints still works but is deprecated from OCP 4.20)

# 4. PODS — are any running and matching the selector?
oc get pods -l app=hello
# If zero pods → Fault D (replicas=0)
# If pods exist but endpoints empty → Fault C (selector doesn't match pod labels)
```

**The decision tree:**

| Symptom in the walk | Fault | 
|---------------------|-------|
| Route `to.name` names a service that doesn't exist | A (wrong service name) |
| Route `targetPort` ≠ the port the pod serves; endpoints healthy | B (wrong targetPort) |
| Service selector ≠ pod labels; endpoints empty; pods running | C (selector mismatch) |
| No pods at all; endpoints empty | D (no running pods) |

**Endpoints are the linchpin.** Populated endpoints mean Service→Pod wiring is good, so the fault is upstream (Route). Empty endpoints mean the Service isn't finding ready pods, so the fault is the selector or the pods themselves.

</details>

---

#### Step 3 — Fix and confirm 200

<details>
<summary>💡 Solution</summary>

Apply the fix matching the fault you found:

```bash
# Fix A — point the route back at the real service
oc patch route hello --type=merge -p '{"spec":{"to":{"name":"hello"}}}'

# Fix B — correct the targetPort
oc patch route hello --type=merge -p '{"spec":{"port":{"targetPort":8080}}}'

# Fix C — restore the correct selector
oc patch service hello --type=merge -p '{"spec":{"selector":{"app":"hello"}}}'

# Fix D — scale pods back up
oc scale deployment hello --replicas=1
```

**Confirm the whole chain is healthy again:**

```bash
oc get endpointslices -l kubernetes.io/service-name=hello
# hello-xxxxx   IPv4   8080   10.x.x.x     ← populated again

curl -sI http://$ROUTE | head -1
# HTTP/1.1 200 OK
```

**General troubleshooting reflexes for the exam:**

```bash
oc get route <r> -o yaml           # spec.to.name, spec.port.targetPort
oc get svc <s> -o wide             # selector, ports
oc get endpointslices -l kubernetes.io/service-name=<s>   # empty = the smoking gun
oc get pods -l <selector> -o wide  # running? right labels?
oc describe route <r>              # router admission errors, host conflicts
oc logs -n openshift-ingress deploy/router-default | tail  # router-side clues
```

**Cleanup:**

```bash
oc delete project lab54
```

</details>

---

---

### Lab 5.5 — Internal TLS with service serving certificates (25 min)

Secure pod-to-service traffic with a certificate issued by OpenShift's service CA, verify it from a client pod that trusts the injected CA bundle, then expose it with a re-encrypt route.

**Prerequisites:**
- Project: `oc new-project lab55`.
- The `nginx-ssl-conf` approach from Lab 5.2 (it's repeated below, so you don't need to have done 5.2).

1. Create a Service `secure` (port 8443) annotated to receive a serving certificate in Secret `secure-tls`.
2. Deploy a UBI nginx that serves TLS on 8443 using that Secret.
3. Create a ConfigMap with the injected service CA, and `curl` the Service over HTTPS from a client pod **without** `-k`.
4. Expose it with a re-encrypt route that needs no destination CA.

<details>
<summary>💡 Solution Step 1</summary>

Create the Service first, so the certificate exists before the pod needs it:

```bash
oc new-project lab55

oc create service clusterip secure --tcp=8443:8443
oc annotate service secure service.beta.openshift.io/serving-cert-secret-name=secure-tls

oc get secret secure-tls
# NAME         TYPE                DATA   AGE
# secure-tls   kubernetes.io/tls   2      5s

# Which names is it valid for?
oc get secret secure-tls -o jsonpath='{.data.tls\.crt}' | base64 -d \
  | openssl x509 -noout -subject -ext subjectAltName
# subject=CN=secure.lab55.svc
# X509v3 Subject Alternative Name:
#     DNS:secure.lab55.svc, DNS:secure.lab55.svc.cluster.local
```

`oc create service clusterip secure` sets the selector `app=secure`, which the Deployment in Step 2 uses.

</details>

<details>
<summary>💡 Solution Step 2</summary>

```bash
cat > nginx-ssl.conf <<'EOF'
server {
    listen 8443 ssl;
    ssl_certificate     /etc/nginx/tls/tls.crt;
    ssl_certificate_key /etc/nginx/tls/tls.key;
    location / { return 200 "hello over internal TLS\n"; }
}
EOF
oc create configmap nginx-ssl-conf --from-file=default.conf=nginx-ssl.conf

cat <<'EOF' | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: secure
spec:
  replicas: 1
  selector: {matchLabels: {app: secure}}
  template:
    metadata: {labels: {app: secure}}
    spec:
      containers:
      - name: nginx
        image: registry.access.redhat.com/ubi9/nginx-124:latest
        command: ["nginx","-g","daemon off;"]   # the image's default command only prints usage
        ports:
        - {containerPort: 8443}
        volumeMounts:
        - {name: tls, mountPath: /etc/nginx/tls, readOnly: true}
        - {name: conf, mountPath: /opt/app-root/etc/nginx.d, readOnly: true}
      volumes:
      - {name: tls, secret: {secretName: secure-tls}}
      - {name: conf, configMap: {name: nginx-ssl-conf}}
EOF

oc rollout status deployment/secure
oc get endpointslices -l kubernetes.io/service-name=secure      # 1 address on 8443
```

</details>

<details>
<summary>💡 Solution Step 3</summary>

```bash
oc create configmap service-ca
oc annotate configmap service-ca service.beta.openshift.io/inject-cabundle=true
oc get configmap service-ca -o jsonpath='{.data}' | cut -c1-60
# {"service-ca.crt":"-----BEGIN CERTIFICATE-----...
```

Run a client that mounts the CA and verifies the server certificate:

```bash
cat <<'EOF' | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: client
spec:
  restartPolicy: Never
  containers:
  - name: curl
    image: registry.access.redhat.com/ubi9/ubi-minimal:latest
    command: ["curl","-sS","--cacert","/etc/ca/service-ca.crt","https://secure.lab55.svc:8443"]
    volumeMounts:
    - {name: ca, mountPath: /etc/ca, readOnly: true}
  volumes:
  - {name: ca, configMap: {name: service-ca}}
EOF

oc logs client        # once the pod has Completed
# hello over internal TLS
```

No `-k`: curl verified the chain against the service CA and the hostname against the certificate's SAN. Try `https://<pod-IP>:8443` instead and it fails with a name-mismatch error — the certificate is for the **Service name**, not the pod.

</details>

<details>
<summary>💡 Solution Step 4</summary>

```bash
oc create route reencrypt secure --service=secure --port=8443
curl -sk https://$(oc get route secure -o jsonpath='{.spec.host}')
# hello over internal TLS
```

Two TLS legs: client → router uses the router's default (wildcard) certificate (hence `-k` with a self-signed ingress CA), router → pod uses the service serving certificate. No `--dest-ca-cert` was needed because the router trusts the service CA.

**Verification checklist:**

```bash
oc get svc secure -o jsonpath='{.metadata.annotations.service\.beta\.openshift\.io/serving-cert-secret-name}{"\n"}'   # secure-tls
oc get secret secure-tls -o jsonpath='{.type}{"\n"}'                                                                    # kubernetes.io/tls
oc get cm service-ca -o jsonpath='{.metadata.annotations}{"\n"}'                                                        # inject-cabundle
oc get route secure -o jsonpath='{.spec.tls.termination}{"\n"}'                                                         # reencrypt
```

Cleanup: `oc delete project lab55`

</details>

---

## ⚡ Drills (timed, no docs)

| Drill | Target time |
|-------|-------------|
| Create an edge Route with TLS files + HTTPS redirect | 90 s |
| Create a passthrough Route | 30 s |
| Write a NetworkPolicy denying all ingress to a namespace | 60 s |
| Write a NetworkPolicy allowing ingress from `app=client` only | 90 s |
| Allow the OpenShift router to reach pods in your namespace | 90 s |
| Patch a Route to change its hostname | 30 s |
| Get a service serving certificate into a Secret and inject the CA into a ConfigMap | 60 s |

---

## ❗ Common pitfalls

1. **`tls.key`, `tls.certificate`, `tls.caCertificate` must be inline (PEM)**, not file references, in the Route YAML. Use `--cert/--key` flags or `oc create -f` with inline PEM.
2. **A passthrough Route requires a Service whose targetPort matches a TLS port on the pod.**
3. **Once any NetworkPolicy exists in a namespace, default-allow disappears for pods matching its podSelector.** A common mistake: writing an "allow X" policy without realising you've also blocked everything else.
4. **The router namespace must be allowed in ingress NetworkPolicies** — many candidates write strict policies that accidentally lock out the router and break their own Route.
5. **DNS uses `<svc>.<ns>.svc.cluster.local`** — wrong namespace = NXDOMAIN.
6. **Egress policies must allow DNS on port 5353** (the DNS pods' port), not just 53.
7. **HostNetwork routers** (CRC, SNO, bare metal) need the `policy-group.network.openshift.io/host-network` selector in your allow-from-router policy.

## 🔗 Docs to bookmark

Since 4.18 the networking docs are split into several guides (*Ingress and load balancing*, *Network security*, *Networking Operators*, …). Swap `4.18` for your exam's version; if a page 404s, open the guide's `index` page.

- Routes, incl. edge / passthrough / re-encrypt: <https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/ingress_and_load_balancing/routes>
- Network policy: <https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/network_security/network-policy>
- Ingress Operator / IngressController: <https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/networking_operators/configuring-ingress>
- Service serving certificates & CA bundle injection (*Security and compliance* → "Configuring certificates" → "Securing service traffic using service serving certificate secrets"): <https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/security_and_compliance/configuring-certificates>

---

<div align="center">

[⬅️ Prev: Authentication & authorization](./04-auth-and-authorization.md) &nbsp;·&nbsp; [🏠 Home](../README.md) &nbsp;·&nbsp; [Next: Expose non-HTTP/SNI applications ➡️](./06-expose-non-http-sni.md)

</div>
