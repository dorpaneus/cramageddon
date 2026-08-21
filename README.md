# 💥 Cramageddon

> **Cram** *(v.)* — to force knowledge into a brain under pressure.
> **-ageddon** *(suf.)* — at scale, and slightly out of control.

A personal reference vault for cloud-native and infrastructure certifications.
One folder per exam, each mapped to the official objectives and filled with dense notes,
runnable commands, YAML manifests, hands-on labs, and mock exams.

Built to serve two purposes equally: **preparing** for an exam the first time, and
**coming back later** to refresh a topic that has gone rusty.

Plain Markdown, no build step, no site generator — `grep`-friendly and readable from a
terminal.

---

## ⚠️ Read this first

> This is a **personal knowledge base**, published openly in case it helps someone else.
>
> - **Not accepting pull requests or contributions.** The structure and notation reflect
>   how *I* learn. If something here is useful to you, fork it and make it yours
>   (MIT — no permission needed).
> - **No accuracy guarantees.** Notes are assembled from official docs, vendor
>   documentation, community labs, my own lab runs, and AI-assisted summaries. They may
>   contain mistakes, oversimplifications, or content that has gone stale as exam versions
>   move. **Always verify against the official curriculum and vendor docs** — those are the
>   only authoritative sources. Links to them live in each track's README.
> - **Exam versions drift.** Every track states the product or curriculum version it
>   targets. Confirm that version is still current before trusting a page.

---

## 📚 Repository Index

| Certification | Focus Areas / Key Topics | Folder Link | Status |
| :--- | :--- | :--- | :--- |
| **CKA** | Core Architecture, Scheduling, Networking, Troubleshooting, Etcd | [Explore CKA](./cka) | In Progress |
| **EX280** | Red Hat OpenShift, RBAC, Operators, Route/Ingress, Security Contexts | [Explore EX280](./ex280) | In Progress |
| **KCNA** | Cloud-Native Fundamentals, GitOps, CNCF Ecosystem, Observability | [Explore KCNA](./kcna) | In Progress |
| **Terraform Associate** | IaC, State Management, Modules, Provisioners, Workflows | [Explore Terraform](./terraform) | In Progress |


### EX280 — OpenShift Administration
Targets **OCP 4.18**. One file per official Red Hat objective, each holding YAML manifests,
`oc` command references, and labs with worked solutions behind collapsible blocks. Includes
a persistent-storage supplement — dropped as a standalone objective in 4.18, but still
surfacing inside other tasks — plus mock exams and a couple of career-direction essays on
moving from OpenShift and Linux admin work toward AI and VM platform engineering.

### CKA — Kubernetes Administrator
Targets **curriculum v1.35 / Kubernetes v1.34**. Organised by CNCF domain and weighted
accordingly, with Troubleshooting (30%) and Cluster Architecture (25%) carrying the most
material. Covers exam mechanics, scenario labs (RBAC and friends), and what changed in the
post-Feb-2025 exam: Helm, Kustomize, Gateway API, CRDs and operators, workload autoscaling,
and Pod Security Standards.

### KCNA — Cloud Native Associate
Concept-first coverage of the four official domains, calibrated to their published weights.
Each topic pairs mental models with hands-on reinforcement and active-recall drills. The
exam is conceptual rather than performance-based, so the labs exist to make ideas stick
rather than to rehearse exam tasks.

### Terraform Associate
Written for people who already have IaC experience — particularly Ansible — so it leans on
the declarative-vs-procedural mindset shift and on state management, the concept that most
distinguishes Terraform from what you already know.

---

## 🗂️ Layout

```
cramageddon/
├── README.md          ← you are here
├── LICENSE            ← MIT
│
├── ex280/             ← Red Hat EX280 (OpenShift 4.18)
│   ├── README.md          ← objective index
│   ├── objectives/        ← one file per official exam objective
│   ├── ch/                ← supplementary chapters
│   ├── mock-exams/        ← timed mocks
│   └── *.md               ← career / positioning notes
│
├── cka/               ← CNCF CKA (curriculum v1.35)
│   ├── README.md          ← exam at a glance + domain weighting
│   ├── 00-overview/       ← exam mechanics, cheatsheets
│   ├── 01-cluster-architecture/
│   ├── 02-workloads-scheduling/
│   ├── 04-storage/
│   └── 09-labs/           ← scenario-based practice labs
│
├── kcan/              ← CNCF KCNA
│   ├── README.md          ← topic index by domain
│   └── 14-days/           ← topic notes
│
└── terraform/         ← HashiCorp Terraform Associate
    └── README.md
```

Each track's own `README.md` is the entry point — exam at a glance, domain weighting, and
the index of every topic in that folder.

---

## 🧭 Conventions

Files follow a consistent shape so any track feels familiar, and so a single page works
both as a first pass and as a later refresher:

1. **Objective** — the exact wording from the official curriculum
2. **Why it matters** — weight, and how often it actually shows up
3. **Key concepts** — short and dense, not tutorial prose
4. **Hands-on** — real commands and manifests, runnable as-is
5. **Exercises** — timed and exam-style, with worked solutions hidden behind collapsible blocks
6. **Common pitfalls** — the things that cost points
7. **Doc bookmarks** — exact pages to pre-open, since these exams are open-book

Skim sections 3 and 4 to review a topic; work 4 through 6 to actually learn it. Mock exams
are meant to be taken timed, with only the permitted documentation open — no AI, no search.
Grading is on end state, not on how you got there.

---

## 🧰 Lab environment

Nothing here is theoretical — every track assumes somewhere to break things.

| Track | Practice environment |
|---|---|
| EX280 | OpenShift Local (CRC), Red Hat Developer Sandbox, or your own cluster |
| CKA | `kind`, `minikube`, `k3d`, or two cheap VMs for a real `kubeadm` install |
| KCNA | Minikube or Kind — enough to run a Pod and read the API |
| Terraform | Any cloud free tier, plus a remote backend to see state locking work |

Useful to have on `$PATH`: `oc`, `kubectl`, `helm`, `kustomize`, `terraform`, `jq`, `yq`,
and an editor you can drive without a mouse (`vim`/`vi`) — the performance-based exams give
you a terminal and nothing else.

---

## 🔗 Authoritative sources

These always outrank anything written here:

- **Red Hat EX280** — <https://www.redhat.com/en/services/training/red-hat-certified-openshift-administrator-exam>
- **OpenShift 4.18 docs** — <https://docs.redhat.com/en/documentation/openshift_container_platform/4.18>
- **CNCF curricula (CKA / KCNA)** — <https://github.com/cncf/curriculum>
- **Linux Foundation certifications** — <https://training.linuxfoundation.org/certification/>
- **Kubernetes docs** — <https://kubernetes.io/docs/>
- **HashiCorp Terraform certification** — <https://developer.hashicorp.com/certifications/infrastructure-automation>

---

## 📄 License

[MIT](./LICENSE). Fork it, rewrite it, sell nothing back to me.

---

*Discipline beats intelligence here. Practice the boring things.*
