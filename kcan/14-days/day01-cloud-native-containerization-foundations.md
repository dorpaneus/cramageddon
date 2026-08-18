# Day 1 — Cloud Native & Containerization Foundations

> **Domain coverage:** Kubernetes Fundamentals → *Containerization* · plus the conceptual groundwork for Cloud Native Architecture
> **Goal for today:** Understand *what* cloud native is and *why* containers exist before touching Kubernetes itself. By tonight you'll have a working local lab and your first running Pod.

**Today's objectives**

- [ ] Define "cloud native" and name its core characteristics
- [ ] Explain how the CNCF organizes the ecosystem (maturity levels)
- [ ] Articulate the difference between containers and virtual machines
- [ ] Identify the OCI specs, container runtimes, and the CRI
- [ ] Install your toolchain (Docker, `kubectl`, Minikube **or** Kind)
- [ ] Launch a local cluster and apply your first Pod manifest

---

## 🌅 Morning Block — Concepts

### 1. What does "cloud native" actually mean?

Cloud native is **an approach to building and running applications that fully exploits the elasticity and automation of cloud platforms** — public, private, or hybrid. It's not a single product; it's a set of practices and technologies that make applications **scalable, resilient, observable, and frequently changeable**.

The CNCF (Cloud Native Computing Foundation) defines the approach by five recurring building blocks. Memorize these — they appear repeatedly on the exam:

| Building block | Mental model |
|---|---|
| **Containers** | Package an app + its dependencies into one portable, isolated unit. |
| **Microservices** | Decompose a system into small, independently deployable services. |
| **Service meshes** | A dedicated infrastructure layer for service-to-service communication (traffic, security, observability). |
| **Immutable infrastructure** | Servers/containers are never patched in place — you replace them with a new version. |
| **Declarative APIs** | You describe the *desired state*; the system continuously reconciles reality toward it. |

> 🔑 **The single most important cloud-native idea: declarative + desired state.** You tell Kubernetes "I want 3 replicas running"; Kubernetes figures out *how* and keeps it true. This is the opposite of imperative scripting ("run this, then that").

**Why organizations go cloud native:** faster, more frequent releases; self-healing systems; better resource utilization; portability across clouds (avoiding lock-in); and the ability to scale individual components independently.

### 2. The CNCF and how the ecosystem is organized

The **CNCF** is a vendor-neutral home (under the Linux Foundation) for open-source cloud-native projects. It hosts Kubernetes and hundreds of other projects, runs the conformance program, and publishes the **Cloud Native Landscape** (the famous wall-of-logos map).

Projects move through three **maturity levels** — know the order and what each signals:

| Level | What it signals |
|---|---|
| **Sandbox** | Early-stage, experimental, for innovation and early adopters. |
| **Incubating** | Growing adoption, used in production by a meaningful number of users. |
| **Graduated** | Mature, widely adopted, stable governance. The highest tier. |

**Graduated projects worth recognizing by name:** Kubernetes, Prometheus, Envoy, containerd, CoreDNS, etcd, Helm, Fluentd, Argo, Harbor, Open Policy Agent (OPA). You don't need the full list, but you *should* be able to say what each graduated project broadly does.

> ⚠️ **Exam trap:** The order is **Sandbox → Incubating → Graduated**. People often flip the first two. Sandbox is the *least* mature.

### 3. Containers vs. Virtual Machines

This comparison is almost guaranteed to appear. The core distinction is **what gets virtualized**.

```
   VIRTUAL MACHINES                      CONTAINERS
 ┌─────────┬─────────┐               ┌──────┬──────┬──────┐
 │  App A  │  App B  │               │ App A│ App B│ App C│
 ├─────────┼─────────┤               ├──────┼──────┼──────┤
 │ Bins/Lib│ Bins/Lib│               │Bins/L│Bins/L│Bins/L│
 ├─────────┼─────────┤               ├──────┴──────┴──────┤
 │ Guest OS│ Guest OS│               │  Container Runtime  │
 ├─────────┴─────────┤               ├────────────────────┤
 │     Hypervisor    │               │     Host OS         │
 ├───────────────────┤               ├────────────────────┤
 │      Host OS       │              │     Hardware        │
 ├───────────────────┤               └────────────────────┘
 │     Hardware      │
 └───────────────────┘
```

| | Virtual Machine | Container |
|---|---|---|
| Virtualizes | Hardware | The operating system |
| Includes a guest OS? | **Yes** (heavy) | **No** — shares the host kernel |
| Size | Gigabytes | Megabytes |
| Startup time | Seconds–minutes | Milliseconds–seconds |
| Isolation | Strong (separate kernel) | Lighter (process-level) |
| Density per host | Lower | Much higher |

> 🔑 The key sentence to remember: **containers share the host OS kernel; VMs each run their own full guest OS.** That single fact explains every speed/size/density difference above.

### 4. What a container actually *is* (Linux primitives)

A container isn't magic — it's a normal process that the Linux kernel has isolated using three features. Recognizing these names is enough for KCNA:

- **Namespaces** → provide *isolation* (the process gets its own view of PIDs, network, mounts, users, hostname).
- **cgroups** (control groups) → provide *resource limits* (how much CPU/memory the process may use).
- **Union/overlay filesystems** → enable *layered images* (images are built from stacked, cacheable, read-only layers + a writable top layer).

### 5. OCI, container runtimes, and the CRI

Standards keep the ecosystem interoperable. Three acronyms matter:

- **OCI (Open Container Initiative)** — defines the open standards so images and runtimes are portable across tools. Three specs:
  - **image-spec** — what a container image looks like.
  - **runtime-spec** — how to run a container from that image.
  - **distribution-spec** — how images are pushed/pulled from registries.
- **Container runtimes** come in two layers:
  - **Low-level:** `runc` — actually creates the container using kernel primitives.
  - **High-level:** `containerd`, `CRI-O` — manage images, networking, and call the low-level runtime.
- **CRI (Container Runtime Interface)** — the standard API Kubernetes uses to talk to *any* compliant runtime. This is why Kubernetes is runtime-agnostic.

> ⚠️ **"Did Kubernetes remove Docker?"** Kubernetes removed **dockershim** (the shim for talking to Docker Engine) in v1.24. Your Docker-built images still run fine — because they're **OCI images** — and Kubernetes talks to `containerd`/`CRI-O` via the CRI. Docker the *tool* is still great for building; it's just not a cluster runtime.

### 6. Where Kubernetes fits

Containers solve *packaging*. But running hundreds of containers across many machines — scheduling them, restarting failures, networking them, scaling them — needs an **orchestrator**. That's Kubernetes, and it's where the rest of this course goes (starting tomorrow with its architecture).

---

## ⌨️ Midday Block — Hands-on

> **Pick one local cluster tool.** **Minikube** is the most beginner-friendly (rich addons, single-node VM/container). **Kind** ("Kubernetes IN Docker") is lightweight and fast. Either is fine for KCNA prep. Commands for both are shown.

### Lab 1 — Install the toolchain

**kubectl** (the Kubernetes CLI — you'll use this every single day):

```bash
# Linux (x86-64). Always pulls the current stable release.
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client
```

> macOS: `brew install kubectl` · Windows: `choco install kubernetes-cli` or `winget install kubectl`

**Minikube** (option A):

```bash
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
minikube version
```

**Kind** (option B) — requires Docker installed first:

```bash
# Install Docker first if you don't have it, then:
[ "$(uname -m)" = "x86_64" ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64
chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind
kind version
```

### Lab 2 — Docker fundamentals (the packaging layer)

```bash
docker run hello-world                 # pulls + runs a tiny test image
docker run -d -p 8080:80 --name web nginx   # run nginx detached, map host:8080 -> container:80
docker ps                              # list running containers
docker images                          # list local images
docker logs web                        # view container logs
docker exec -it web /bin/sh            # open a shell INSIDE the container (type 'exit' to leave)
docker stop web && docker rm web       # stop and remove
```

**Build your own image.** Create a file named `Dockerfile`:

```dockerfile
FROM nginx:alpine
RUN echo "<h1>Hello from my first container image</h1>" > /usr/share/nginx/html/index.html
EXPOSE 80
```

```bash
docker build -t my-first-image:1.0 .
docker run -d -p 8081:80 my-first-image:1.0
curl localhost:8081      # should return your custom HTML
```

> 💡 Notice how each `Dockerfile` instruction becomes an **image layer** — that's the union filesystem from this morning in action.

### Lab 3 — Start your first cluster

```bash
# Minikube:
minikube start
minikube status

# OR Kind:
kind create cluster --name kcna
```

### Lab 4 — First contact with kubectl

```bash
kubectl cluster-info          # control plane endpoints
kubectl get nodes             # your cluster's node(s)
kubectl get nodes -o wide     # more detail (versions, IPs, runtime)
kubectl get pods -A           # all pods in ALL namespaces (note the system pods!)
kubectl get namespaces        # the namespaces that exist by default
```

Look closely at `kubectl get pods -A` — you'll see pods like `kube-apiserver`, `etcd`, `coredns`, `kube-scheduler`. **Those are the control-plane components we cover tomorrow.** You're seeing Kubernetes run itself.

### Lab 5 — Imperative vs. declarative (your first Pod)

**Imperative** (quick, one-off):

```bash
kubectl run nginx-imperative --image=nginx
kubectl get pods
```

**Declarative** (the cloud-native way). Create `first-pod.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-declarative
  labels:
    app: web
spec:
  containers:
    - name: nginx
      image: nginx:alpine
      ports:
        - containerPort: 80
```

```bash
kubectl apply -f first-pod.yaml         # declare desired state
kubectl get pods                        # watch it appear
kubectl describe pod nginx-declarative  # events, image, status — your debugging best friend
kubectl logs nginx-declarative          # container logs
kubectl delete -f first-pod.yaml        # clean up by file
```

> 🔑 You just experienced the central distinction: `kubectl run` *tells* Kubernetes what to do; `kubectl apply -f` *declares* what should exist. Everything from here on favors the declarative file approach.

**Tidy up (optional):**
```bash
kubectl delete pod nginx-imperative
# minikube stop   (or)   kind delete cluster --name kcna
```

---

## 🎯 Afternoon Block — Drills

Answer each before expanding. No peeking — active recall is what makes this stick.

**Q1.** In one sentence, what is the fundamental technical difference between a container and a virtual machine?

<details>
<summary>Show answer</summary>

A container **shares the host operating system's kernel** and isolates a process, whereas a virtual machine **runs its own full guest OS** on top of a hypervisor. This is why containers are smaller, faster to start, and denser per host.
</details>

**Q2.** Name the five building blocks the CNCF uses to characterize cloud native.

<details>
<summary>Show answer</summary>

Containers, microservices, service meshes, immutable infrastructure, and declarative APIs.
</details>

**Q3.** Put the CNCF project maturity levels in order from least to most mature.

<details>
<summary>Show answer</summary>

**Sandbox → Incubating → Graduated.** Sandbox is the least mature (experimental); Graduated is the most mature (widely adopted, stable governance).
</details>

**Q4.** Which Linux kernel features provide (a) isolation and (b) resource limits for containers?

<details>
<summary>Show answer</summary>

(a) **Namespaces** provide isolation (separate views of PIDs, network, mounts, etc.). (b) **cgroups** (control groups) provide resource limits (CPU, memory). Union/overlay filesystems handle the layered image part.
</details>

**Q5.** What are the three OCI specifications, and what does each define?

<details>
<summary>Show answer</summary>

- **image-spec** — the format of a container image.
- **runtime-spec** — how to run a container from an image.
- **distribution-spec** — how images are pushed to and pulled from registries.
</details>

**Q6.** Kubernetes "removed Docker." What was actually removed, and can you still run images you built with Docker?

<details>
<summary>Show answer</summary>

Kubernetes removed **dockershim** (the component for talking to Docker Engine as a runtime) in v1.24. Yes — images built with Docker still run fine, because they are **OCI-compliant images**. Kubernetes talks to runtimes like **containerd** or **CRI-O** through the **CRI**.
</details>

**Q7.** What does the **CRI** do, and why does it matter?

<details>
<summary>Show answer</summary>

The **Container Runtime Interface** is the standard API the kubelet uses to communicate with a container runtime. It matters because it makes Kubernetes **runtime-agnostic** — any CRI-compliant runtime (containerd, CRI-O) can be plugged in.
</details>

**Q8.** Distinguish a *low-level* from a *high-level* container runtime, with an example of each.

<details>
<summary>Show answer</summary>

A **low-level runtime** (e.g., `runc`) actually creates the container using kernel primitives. A **high-level runtime** (e.g., `containerd`, `CRI-O`) manages images, pulling, and networking, then delegates the actual container creation to the low-level runtime.
</details>

**Q9.** What is the difference between an *imperative* and a *declarative* approach in Kubernetes? Give a command example of each.

<details>
<summary>Show answer</summary>

**Imperative** = you issue commands describing *actions* (`kubectl run nginx --image=nginx`). **Declarative** = you describe the *desired end state* in a manifest and apply it (`kubectl apply -f pod.yaml`); Kubernetes reconciles reality toward that state. Declarative is the cloud-native default.
</details>

**Q10.** In a Pod manifest, what do the top-level fields `apiVersion`, `kind`, `metadata`, and `spec` represent?

<details>
<summary>Show answer</summary>

- **apiVersion** — which version of the Kubernetes API this object uses (e.g., `v1`).
- **kind** — the type of object (e.g., `Pod`).
- **metadata** — identifying data (name, labels, annotations, namespace).
- **spec** — the desired state / configuration of the object (e.g., which containers and images to run).
</details>

**Q11.** Why is "immutable infrastructure" considered more reliable than patching servers in place?

<details>
<summary>Show answer</summary>

Because you never modify a running instance — you **replace** it with a freshly built, tested version. This eliminates configuration drift, makes deployments reproducible, and makes rollbacks trivial (just redeploy the previous image).
</details>

**Q12.** You ran `kubectl get pods -A` and saw pods named `etcd`, `kube-apiserver`, and `coredns`. What are these, broadly?

<details>
<summary>Show answer</summary>

They are **Kubernetes' own control-plane / system components** running as pods. `kube-apiserver` is the front door to the cluster, `etcd` is the cluster's data store, and `coredns` provides in-cluster DNS. (Full detail tomorrow.)
</details>

---

## ✅ Key Takeaways

- **Cloud native = scalable, resilient apps built on containers, microservices, service meshes, immutable infrastructure, and declarative APIs.**
- The defining cloud-native mindset is **declarative / desired-state**, not imperative scripting.
- **Containers share the host kernel; VMs don't** — that one fact explains all the size/speed/density differences.
- Containers are built from **namespaces (isolation) + cgroups (limits) + layered filesystems**.
- **OCI** standardizes images/runtimes/distribution; the **CRI** lets Kubernetes use any compliant runtime; Docker images still work everywhere.
- CNCF maturity goes **Sandbox → Incubating → Graduated**.

## 🔜 Tomorrow — Day 2: Kubernetes Architecture & Core Concepts

We dissect those system pods you just saw: the **control plane** (api-server, etcd, scheduler, controller-manager) and the **worker nodes** (kubelet, kube-proxy, runtime) — and trace exactly what happens when you run `kubectl apply`.
