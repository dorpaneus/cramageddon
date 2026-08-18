# Objective 6 — Expose non-HTTP/SNI Applications

> **Exam study points:**
> - Configure a load balancer service
> - Configure external application access

OpenShift Routes only handle HTTP/HTTPS (with SNI). For raw TCP (databases, gRPC over arbitrary ports, MQTT), UDP, or HTTP without SNI, you use **Services of type `NodePort`, `LoadBalancer`, or `ExternalIP`**.

---

## §1 — Three ways to expose non-HTTP traffic

| Type | What it gives you | When to use |
|------|-------------------|-------------|
| **`NodePort`** | A port (default 30000–32767) opened on **every node** | On-prem / CRC / when no cloud LB is available |
| **`LoadBalancer`** | A cloud provider LB with a real external IP | AWS / Azure / GCP / IBM / on-prem with MetalLB |
| **`ExternalIP`** | Any IP on a `spec.externalIPs` list | Self-managed bare-metal; you own DNS to that IP |

You may also see references to **`TLS-with-SNI` passthrough Routes** — but per Red Hat's objective wording, "non-HTTP/SNI" really means: anything where you can't rely on the HAProxy router.

## §2 — NodePort

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mysql
spec:
  type: NodePort
  selector: { app: mysql }
  ports:
    - name: mysql
      port: 3306             # Service port (cluster-internal)
      targetPort: 3306       # Pod containerPort
      nodePort: 30306        # External port on every node (optional; allocated if omitted)
      protocol: TCP
```

```bash
# Imperative
oc expose deployment/mysql --port=3306 --target-port=3306 --type=NodePort --name=mysql

# What node port got assigned?
oc get svc mysql -o jsonpath='{.spec.ports[0].nodePort}'

# Connect
mysql -h <any-node-IP> -P 30306 -uapp -p
```

Considerations:

- Make sure the **firewall on the node** allows traffic to the chosen NodePort.
- On CRC, the relevant node IP is `crc ip` (one node).
- Pod Security Admission still applies; nothing magic about NodePort.

## §3 — LoadBalancer (cloud)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mysql
spec:
  type: LoadBalancer
  selector: { app: mysql }
  ports:
    - { port: 3306, targetPort: 3306, protocol: TCP }
```

```bash
oc expose deployment/mysql --port=3306 --target-port=3306 --type=LoadBalancer

# Wait for the cloud LB
oc get svc mysql -w
oc get svc mysql -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{"\n"}{.status.loadBalancer.ingress[0].ip}'
```

On a cluster with MetalLB installed, the same YAML works on-prem; MetalLB pulls an IP from a pre-configured `IPAddressPool`.

## §4 — ExternalIP

If your cluster permits external IPs, you can set `spec.externalIPs`. The platform admin must add the IP block to the `Network` config:

```yaml
# Cluster-wide allowed external IPs (one-time, by admin)
apiVersion: config.openshift.io/v1
kind: Network
metadata: { name: cluster }
spec:
  externalIP:
    autoAssignCIDRs: []
    policy:
      allowedCIDRs: ["192.168.50.0/24"]
```

Then the Service:

```yaml
apiVersion: v1
kind: Service
metadata: { name: mysql }
spec:
  selector: { app: mysql }
  ports: [{ port: 3306, targetPort: 3306 }]
  externalIPs:
    - 192.168.50.10
```

DNS — point `mysql.example.com` at `192.168.50.10`.

## §5 — A complete example: exposing MySQL over a NodePort

```bash
oc new-project mysql-ext

oc new-app --image=registry.redhat.io/rhel9/mysql-80:latest --name=mysql \
  -e MYSQL_USER=app -e MYSQL_PASSWORD=app -e MYSQL_DATABASE=appdb \
  -e MYSQL_ROOT_PASSWORD=rootpw

oc expose deployment/mysql --port=3306 --target-port=3306 --type=NodePort --name=mysql

NODE_PORT=$(oc get svc mysql -o jsonpath='{.spec.ports[0].nodePort}')
NODE_IP=$(oc get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')
[ -z "$NODE_IP" ] && NODE_IP=$(oc get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

echo "mysql -h ${NODE_IP} -P ${NODE_PORT} -uapp -papp appdb"
```

For CRC, replace `$NODE_IP` with `$(crc ip)`.

---

## 🧪 Labs

### Lab 6.1 — NodePort end-to-end (20 min)

NodePort exposes a service on a static port on every node's IP. This lab runs MySQL (a non-HTTP TCP service that can't use a normal Route) and connects to it from outside the cluster.

**Prerequisites:**
- Project: `oc new-project lab61`.
- A `mysql` client on your workstation (`dnf install mysql` / `apt install default-mysql-client` / `brew install mysql-client`).
- Ability to reach a node's IP on a high port (works on CRC/SNO/bare-metal; may be blocked by cloud security groups on managed clusters).

---

#### Step 1 — Deploy MySQL in `lab61`

<details>
<summary>💡 Solution</summary>

```bash
oc project lab61

oc new-app --image=registry.redhat.io/rhel9/mysql-80:latest --name=mysql \
  -e MYSQL_USER=app \
  -e MYSQL_PASSWORD=app \
  -e MYSQL_DATABASE=appdb \
  -e MYSQL_ROOT_PASSWORD=rootpw

oc rollout status deployment/mysql
oc get pods -l deployment=mysql
# mysql-xxxxx   1/1   Running
```

**If the image needs a pull secret:** `registry.redhat.io` requires Red Hat credentials. On a properly-installed cluster the global pull secret already covers it. If you get `ImagePullBackOff` with an auth error, either use a public image:

```bash
oc new-app --image=quay.io/sclorg/mysql-80-c9s:latest --name=mysql \
  -e MYSQL_USER=app -e MYSQL_PASSWORD=app -e MYSQL_DATABASE=appdb \
  -e MYSQL_ROOT_PASSWORD=rootpw
```

or add your credentials as a pull secret and link it to the SA (see Objective 9 lab on pull secrets).

**Why MySQL for this objective:** it's a raw TCP protocol on port 3306, not HTTP. A standard OpenShift Route (edge/reencrypt) only handles HTTP/HTTPS with hostname routing, so database/TCP services need NodePort, LoadBalancer, or ExternalIP instead. That's exactly what Objective 6 tests.

</details>

---

#### Step 2 — Create a NodePort Service pinned to `30336`

<details>
<summary>💡 Solution</summary>

`oc new-app` already created a ClusterIP service named `mysql`. Replace it with a NodePort, or create a second service. Cleanest is to declare exactly what you want:

```bash
# Delete the auto-created ClusterIP service and make a NodePort with a pinned port
oc delete svc mysql

cat <<EOF | oc apply -f -
apiVersion: v1
kind: Service
metadata:
  name: mysql
  namespace: lab61
spec:
  type: NodePort
  selector:
    deployment: mysql
  ports:
  - port: 3306
    targetPort: 3306
    nodePort: 30336
EOF

oc get svc mysql
# NAME    TYPE       CLUSTER-IP     PORT(S)          AGE
# mysql   NodePort   172.30.x.x     3306:30336/TCP   5s
```

**The three ports on a NodePort service — don't confuse them:**

| Field | Meaning |
|-------|---------|
| `port` | The service's own cluster-internal port (what ClusterIP listens on) |
| `targetPort` | The container port traffic is forwarded to |
| `nodePort` | The static port opened on **every node's IP** for external access |

**nodePort range:** must be within `30000–32767` by default. Pick `30336` here. Omit `nodePort` and Kubernetes auto-assigns a random one in that range.

**Verify the selector matches the pod's labels** (a mismatch = empty endpoints = connection refused):

```bash
oc get pod -l deployment=mysql --show-labels | head
oc get endpoints mysql
# mysql   10.x.x.x:3306    ← must be populated
```

**Imperative alternative:**

```bash
oc expose deployment/mysql --type=NodePort --port=3306 --target-port=3306 --name=mysql
# then patch the random nodePort to 30336:
oc patch svc mysql --type=json \
  -p='[{"op":"replace","path":"/spec/ports/0/nodePort","value":30336}]'
```

</details>

---

#### Step 3 — Connect from your workstation with the `mysql` client

<details>
<summary>💡 Solution</summary>

```bash
# Grab a node IP
NODE_IP=$(oc get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')
[ -z "$NODE_IP" ] && NODE_IP=$(oc get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "Node IP: $NODE_IP"

# On CRC specifically, the reachable IP is the CRC VM IP:
# NODE_IP=$(crc ip)

# Connect
mysql -h "$NODE_IP" -P 30336 -uapp -papp appdb
# Welcome to the MySQL monitor ...
# mysql>
```

**If the connection hangs or is refused:**

| Cause | Check |
|-------|-------|
| Empty endpoints (selector mismatch) | `oc get endpoints mysql` should show a pod IP |
| Pod not ready | `oc get pods -l deployment=mysql` |
| Cloud firewall blocks 30336 | Managed clusters (EKS/AKS/GKE) often block NodePort range in security groups — this lab may only work on CRC/bare-metal |
| Wrong node IP | On multi-node clusters, any node's IP works (kube-proxy forwards), but the IP must be reachable from your workstation |

**On the exam:** NodePort tasks are validated from within the cluster environment where node IPs are reachable, so you won't hit cloud-firewall issues there.

</details>

---

#### Step 4 — Create a table, insert a row, query it, then tear down

<details>
<summary>💡 Solution</summary>

```sql
-- Inside the mysql> prompt:
CREATE TABLE greetings (id INT PRIMARY KEY, msg VARCHAR(50));
INSERT INTO greetings VALUES (1, 'hello from nodeport');
SELECT * FROM greetings;
-- +----+---------------------+
-- | id | msg                 |
-- +----+---------------------+
-- |  1 | hello from nodeport |
-- +----+---------------------+
EXIT;
```

**One-liner version (non-interactive):**

```bash
mysql -h "$NODE_IP" -P 30336 -uapp -papp appdb -e "
  CREATE TABLE greetings (id INT PRIMARY KEY, msg VARCHAR(50));
  INSERT INTO greetings VALUES (1, 'hello from nodeport');
  SELECT * FROM greetings;
"
```

**Verification checklist:**

```bash
oc get svc mysql -o jsonpath='type={.spec.type}{"\t"}nodePort={.spec.ports[0].nodePort}{"\n"}'
# type=NodePort   nodePort=30336
oc get endpoints mysql        # populated
# and the mysql client SELECT returned the row
```

**Tear down:**

```bash
oc delete project lab61
```

</details>

---

### Lab 6.2 — LoadBalancer (cloud or MetalLB only) (20 min)

A `LoadBalancer` service asks the cloud provider (or MetalLB on bare-metal) to provision an external IP/hostname that fronts the service. This lab only works where a load-balancer provider exists.

**Prerequisites:**
- A cluster on AWS/Azure/GCP (cloud LB), **or** MetalLB installed on bare-metal/CRC.
- Project: `oc new-project lab62`.
- If you have neither, skip to Lab 6.3 (ExternalIP) instead.

---

#### Step 1 — Deploy the same MySQL

<details>
<summary>💡 Solution</summary>

```bash
oc project lab62
oc new-app --image=registry.redhat.io/rhel9/mysql-80:latest --name=mysql \
  -e MYSQL_USER=app -e MYSQL_PASSWORD=app -e MYSQL_DATABASE=appdb \
  -e MYSQL_ROOT_PASSWORD=rootpw
oc rollout status deployment/mysql
```

(Same as Lab 6.1 Step 1 — substitute the public `quay.io/sclorg/mysql-80-c9s:latest` image if `registry.redhat.io` isn't accessible.)

</details>

---

#### Step 2 — Create a Service of type `LoadBalancer`

<details>
<summary>💡 Solution</summary>

```bash
oc delete svc mysql 2>/dev/null

cat <<EOF | oc apply -f -
apiVersion: v1
kind: Service
metadata:
  name: mysql-lb
  namespace: lab62
spec:
  type: LoadBalancer
  selector:
    deployment: mysql
  ports:
  - port: 3306
    targetPort: 3306
EOF
```

**Imperative alternative:**

```bash
oc expose deployment/mysql --type=LoadBalancer --port=3306 --target-port=3306 --name=mysql-lb
```

**What happens under the hood:** the cloud-controller-manager watches for `type: LoadBalancer` services and calls the cloud API to provision an actual load balancer (an AWS ELB/NLB, Azure LB, GCP forwarding rule, etc.). MetalLB does the equivalent on bare-metal by assigning an IP from a configured address pool and answering ARP for it.

**Note:** a LoadBalancer service also allocates a NodePort under the hood — the cloud LB forwards to that NodePort on the nodes. You'll see it in `oc get svc -o yaml`.

</details>

---

#### Step 3 — Confirm `status.loadBalancer.ingress` populates within ~60 s

<details>
<summary>💡 Solution</summary>

```bash
oc get svc mysql-lb -w
# NAME       TYPE           CLUSTER-IP     EXTERNAL-IP        PORT(S)
# mysql-lb   LoadBalancer   172.30.x.x     <pending>          3306:31xxx/TCP     ← provisioning
# mysql-lb   LoadBalancer   172.30.x.x     a1b2c3.elb.aws...  3306:31xxx/TCP     ← ready
```

**The `EXTERNAL-IP` column** goes from `<pending>` to an IP (cloud IP or MetalLB IP) or a hostname (AWS gives a DNS name). Extract it:

```bash
# IP-based (Azure/GCP/MetalLB):
oc get svc mysql-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}{"\n"}'

# Hostname-based (AWS):
oc get svc mysql-lb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{"\n"}'
```

**If it stays `<pending>` forever:** there's no LoadBalancer provider. Either you're on plain CRC without MetalLB, or the cloud integration isn't configured. Confirm with:

```bash
oc get pods -n openshift-cloud-controller-manager 2>/dev/null
oc get pods -n metallb-system 2>/dev/null
```

No provider → use Lab 6.3 instead.

</details>

---

#### Step 4 — Connect over the external IP/hostname

<details>
<summary>💡 Solution</summary>

```bash
LB=$(oc get svc mysql-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
[ -z "$LB" ] && LB=$(oc get svc mysql-lb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "LB endpoint: $LB"

mysql -h "$LB" -P 3306 -uapp -papp appdb -e "SELECT 'hello from LB' AS greeting;"
# +---------------+
# | greeting      |
# +---------------+
# | hello from LB |
# +---------------+
```

**Gotcha — cloud security groups:** even with an external IP, the cloud firewall must allow inbound 3306. Managed OpenShift usually opens the LB's ports automatically, but a custom security posture might block it. If the connection times out but the service shows an external IP, suspect the firewall.

**NodePort vs LoadBalancer — when to use which:**

| Type | External access | Needs cloud/MetalLB? | Typical use |
|------|-----------------|----------------------|-------------|
| `NodePort` | `<nodeIP>:<30000-32767>` | No | Labs, on-prem, quick TCP exposure |
| `LoadBalancer` | Dedicated external IP/hostname | **Yes** | Production TCP services in cloud |
| `ExternalIP` | An IP you route to a node | No (you handle routing) | On-prem with manual IP management |

**Cleanup:**

```bash
oc delete project lab62
# (This also releases the cloud load balancer — important to avoid ongoing charges.)
```

</details>

---

### Lab 6.3 — ExternalIP simulation on CRC (20 min)

`externalIPs` lets you assign a specific IP to a service; you're responsible for routing that IP to a cluster node. This lab does it on CRC where there's no cloud LB. The exam may test the cluster-side config even if you never route real traffic.

**Prerequisites:**
- CRC (or any cluster where you control the host network routing).
- Cluster-admin.
- Project: `oc new-project lab63`, with MySQL deployed as in Lab 6.1 Step 1.
- Linux host (the `ip route add` step is Linux-specific).

---

#### Step 1 — Allow CRC's network CIDR in `Network.config/cluster`

By default OpenShift rejects `externalIPs` unless the IP falls within an admin-approved CIDR. You must whitelist a range first.

<details>
<summary>💡 Solution</summary>

```bash
# Inspect current external IP policy (likely empty/absent)
oc get network.config/cluster -o jsonpath='{.spec.externalIP}{"\n"}'

# Allow CRC's network range
oc patch network.config/cluster --type=merge -p='
spec:
  externalIP:
    policy:
      allowedCIDRs:
      - 192.168.130.0/24
'

# Verify
oc get network.config/cluster -o jsonpath='{.spec.externalIP.policy.allowedCIDRs}{"\n"}'
# ["192.168.130.0/24"]
```

**What `externalIP.policy` controls:**

| Config | Effect |
|--------|--------|
| `policy` absent | ExternalIPs feature effectively disabled (services can't set externalIPs) |
| `policy.allowedCIDRs: [range]` | Services may use externalIPs **within** those ranges |
| `policy.rejectedCIDRs` | Explicitly forbidden ranges (takes precedence) |
| `autoAssignCIDRs` | Pool from which the cluster auto-assigns externalIPs to LoadBalancer services |

The `192.168.130.0/24` is CRC's default host-only network. On a different environment, use whatever subnet routes to your nodes.

</details>

---

#### Step 2 — Pick an unused IP in that range

<details>
<summary>💡 Solution</summary>

```bash
EXT_IP=192.168.130.99

# Sanity check it's not already in use (should NOT reply):
ping -c1 -W1 $EXT_IP
# (100% packet loss = free to use)
```

Pick something outside the DHCP-assigned area of the subnet to avoid collisions. `.99` in a /24 that CRC uses for `.11` (the VM) is usually safe.

</details>

---

#### Step 3 — Create a Service with that `externalIPs`

<details>
<summary>💡 Solution</summary>

```bash
oc delete svc mysql -n lab63 2>/dev/null

cat <<EOF | oc apply -f -
apiVersion: v1
kind: Service
metadata:
  name: mysql-ext
  namespace: lab63
spec:
  selector:
    deployment: mysql
  ports:
  - port: 3306
    targetPort: 3306
  externalIPs:
  - 192.168.130.99
EOF

oc get svc mysql-ext -n lab63
# NAME        TYPE        CLUSTER-IP     EXTERNAL-IP       PORT(S)
# mysql-ext   ClusterIP   172.30.x.x     192.168.130.99    3306/TCP
```

**Note:** the service `TYPE` stays `ClusterIP` — `externalIPs` is an *additional* field on a ClusterIP service, not a separate type. The EXTERNAL-IP column shows your assigned IP.

**If the apply is rejected** with `spec.externalIPs is not allowed`, Step 1's CIDR whitelist didn't take — re-check the `network.config/cluster` patch.

</details>

---

#### Step 4 — Route the external IP to CRC's VM on your host

<details>
<summary>💡 Solution</summary>

```bash
# Add a host route so the kernel sends traffic for 192.168.130.99 to CRC's VM
sudo ip route add 192.168.130.99 via $(crc ip)

# Verify the route exists
ip route get 192.168.130.99
# 192.168.130.99 via 192.168.130.11 dev crc ...
```

**What this does:** OpenShift's OVN handles the externalIP *inside* the cluster (any node accepts traffic for `.99` and forwards it to the service), but your **host** doesn't know how to reach `.99` yet. The `ip route add` tells your host's kernel "to reach `.99`, send it to the CRC VM." From there OVN takes over.

**macOS note:** the `ip` command doesn't exist; use `sudo route -n add 192.168.130.99 $(crc ip)`. On Windows, routing to the CRC VM is more involved — this lab is easiest on Linux.

</details>

---

#### Step 5 — Connect via the external IP

<details>
<summary>💡 Solution</summary>

```bash
mysql -h 192.168.130.99 -P 3306 -uapp -papp appdb \
  -e "SELECT 'hello from externalIP' AS greeting;"
# +------------------------+
# | greeting               |
# +------------------------+
# | hello from externalIP  |
# +------------------------+
```

**Verification checklist:**

```bash
oc get network.config/cluster -o jsonpath='{.spec.externalIP.policy.allowedCIDRs}'   # includes your CIDR
oc get svc mysql-ext -n lab63 -o jsonpath='{.spec.externalIPs[0]}'                    # 192.168.130.99
ip route get 192.168.130.99                                                          # via $(crc ip)
# and the mysql SELECT returned a row
```

**Cleanup (including the host route and the cluster network patch):**

```bash
sudo ip route del 192.168.130.99 2>/dev/null
oc delete project lab63
# Optionally revert the externalIP policy:
oc patch network.config/cluster --type=json \
  -p='[{"op":"remove","path":"/spec/externalIP"}]'
```

**When ExternalIP matters on the exam:** it's the on-prem answer for "expose this TCP service on a specific IP" when there's no cloud LoadBalancer. The exam-relevant part is usually the *cluster-side* config (whitelisting the CIDR and setting `externalIPs` on the service) — the host routing is environment plumbing that the exam grader handles for you.

</details>

---

---

## ⚡ Drills (timed, no docs)

| Drill | Target time |
|-------|-------------|
| Convert an existing ClusterIP Service to NodePort | 30 s |
| Pin a NodePort to a specific number | 30 s |
| Create a `LoadBalancer` Service for an existing Deployment | 45 s |
| Find the externally usable address of any LB Service | 30 s |
| Add an externalIP to a Service & verify reachability | 90 s |

---

## ❗ Common pitfalls

1. **`port` vs `targetPort` vs `nodePort`**:
   - `port` = the Service's port (`Service:port → Pod:targetPort`).
   - `targetPort` = pod's `containerPort`.
   - `nodePort` = exposed on every node. Optional; auto-allocated if blank.
2. **NodePorts default to 30000–32767.** Outside that range needs cluster config.
3. **Cloud LB Services can take 1-2 minutes** to provision; don't panic at the first `<pending>`.
4. **ExternalIP requires admin config** of `Network.config/cluster` — won't work without it.
5. **MySQL/Postgres/Redis containers usually need an SCC** (anyuid or non-default fsGroup). See `09-application-security.md`.

## 🔗 Docs to bookmark

- Services: https://docs.openshift.com/container-platform/4.18/networking/configuring_ingress_cluster_traffic/overview-traffic.html
- NodePort: https://docs.openshift.com/container-platform/4.18/networking/configuring_ingress_cluster_traffic/configuring-ingress-cluster-traffic-nodeport.html
- LoadBalancer: https://docs.openshift.com/container-platform/4.18/networking/configuring_ingress_cluster_traffic/configuring-ingress-cluster-traffic-load-balancer.html
- ExternalIP: https://docs.openshift.com/container-platform/4.18/networking/configuring_ingress_cluster_traffic/configuring-externalip.html
- MetalLB: https://docs.openshift.com/container-platform/4.18/networking/metallb/about-metallb.html
