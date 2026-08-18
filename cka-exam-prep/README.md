# CKA — Certified Kubernetes Administrator Prep (v1.35 / K8s v1.34)

A 30-day, 3–5 h/day curriculum built around the **official CNCF CKA Curriculum v1.35**.
 One file per official objective, weekly mock exams, and a final full-length mock.

## ⚠️ Personal learning repository

> - This is my **personal study notes** for the CKA exam. I'm publishing it openly
> in case it helps someone else, but please keep the following in mind:
>
> - **Not accepting pull requests or contributions.** This repo reflects my own
>   learning path and notation style. If you spot something useful for *your*
>   prep, fork it and adapt freely (MIT license).
> - **No accuracy guarantees.** Notes are collected from various sources
>   (official docs, blog posts, my own labs, AI-assisted summaries) and may
>   contain mistakes, oversimplifications, or outdated information. **Always
>   verify against the [official Kubernetes docs](https://kubernetes.io/docs/)
>   and the [CNCF CKA Curriculum](https://github.com/cncf/curriculum)** — those
>   are the only authoritative sources.



## 📊 Exam at a glance

| Item | Detail |
| --- | --- |
| Provider | CNCF + Linux Foundation |
| Format | Performance-based (live cluster, terminal) |
| Duration | **2 hours** |
| Questions | ~15–20 tasks |
| Passing score | **66%** |
| K8s version | **v1.34** (curriculum v1.35) |
| Cost | $445 USD (1 free retake) |
| Validity | 2 years |
| Open-book | ✅ `kubernetes.io/docs`, `/blog`, `helm.sh/docs` |

## 🎯 Domain weighting

| # | Domain | Weight |
| - | --- | ---: |
| 1 | [Cluster Architecture, Installation & Configuration](./01-cluster-architecture/README.md) | **25%** |
| 2 | [Workloads & Scheduling](./02-workloads-scheduling/README.md) | **15%** |
| 3 | [Services & Networking](./03-services-networking/README.md) | **20%** |
| 4 | [Storage](./04-storage/README.md) | **10%** |
| 5 | [Troubleshooting](./05-troubleshooting/README.md) | **30%** |

> **Heads-up**: Troubleshooting + Cluster Architecture = **55%**. Two-thirds of your study time should converge there by week 3.

## 📂 Repo layout

```
cka-prep/
├── README.md                            ← you are here
├── 00-overview/                         ← exam mechanics, day-of strategy
├── 01-cluster-architecture/             ← Domain 1 (25%)
├── 02-workloads-scheduling/             ← Domain 2 (15%)
├── 03-services-networking/              ← Domain 3 (20%)
├── 04-storage/                          ← Domain 4 (10%)
├── 05-troubleshooting/                  ← Domain 5 (30%)
├── 06-curriculum/                       ← 30-day plan + lab setup
├── 07-mock-exams/                       ← Weekly mocks + final mock
├── 08-cheatsheets/                      ← kubectl, YAML, JSONPath, vim
└── 09-labs/                             ← scenario-based practice labs
```

Every objective file follows the same shape:

1. **Objective** — exact wording from CNCF v1.35
2. **Why it matters / exam frequency**
3. **Key concepts** — short, dense
4. **Hands-on commands** — `kubectl` + YAML
5. **Exam-style exercises**
6. **Common pitfalls**
7. **Doc bookmarks** — exact pages to pre-open

## 🚀 How to use this repo

1. **Day 0** — Read [`00-overview/`](./00-overview/) end-to-end and set up your lab ([`06-curriculum/lab-setup.md`](./06-curriculum/lab-setup.md)).
2. **Days 1–28** — Follow [`06-curriculum/30-day-plan.md`](./06-curriculum/30-day-plan.md). Each day = 1–3 objective files + hands-on.
3. **Every Sunday** — Take the weekly mock in [`07-mock-exams/`](./07-mock-exams/). Time yourself strictly.
4. **Days 29–30** — Final full mock + killer.sh + weak-area review.

## 🧰 What you need

- A practice cluster — `kind`, `minikube`, `k3d`, or two cheap VMs for `kubeadm` (see [lab-setup](./06-curriculum/lab-setup.md))
- `kubectl`, `helm`, `kustomize`, `jq`, `yq`, `vim`/`vi`
- A subscription to **killer.sh** comes free with the exam — save both attempts for the last week

## ⚠️ What changed in the latest CKA (post-Feb 2025)

If you're reusing older guides, these are the **new/expanded** competencies you must not skip:

- **Helm & Kustomize** (Domain 1) — now examinable for installing cluster components
- **Gateway API** (Domain 3) — `GatewayClass`, `Gateway`, `HTTPRoute` — partial replacement for Ingress
- **CRDs & Operators** (Domain 1) — install, configure, inspect
- **Workload autoscaling** (Domain 2) — HPA (and conceptual awareness of VPA)
- **Extension interfaces** (Domain 1) — CNI, CSI, CRI conceptual + practical
- **Pod Security Standards** (Domain 1, via RBAC/admission) — replaces deprecated PSPs
- **Dynamic volume provisioning** (Domain 4) — explicit objective now

Old guides that still focus on manual etcd backup as the primary admin skill, or that omit Gateway API and Helm — **discard them**.

## 🔗 Authoritative sources used to build this repo

- **CNCF CKA Curriculum v1.35** — https://github.com/cncf/curriculum (the canonical, normative source)
- **Linux Foundation CKA page** — https://training.linuxfoundation.org/certification/certified-kubernetes-administrator-cka/
- **Kubernetes Official Docs** — https://kubernetes.io/docs/
- **Killer.sh** — best simulator (you get 2 free sessions with the exam)
- **Kelsey Hightower — Kubernetes the Hard Way** — https://github.com/kelseyhightower/kubernetes-the-hard-way

## ✅ Pass criteria (self-check before booking)

Before paying $445, you should be able to:

- [ ] Score **≥ 80%** on killer.sh under time pressure (their bar is harder than the real exam)
- [ ] Write a `Deployment`, `Service`, `Ingress`/`HTTPRoute`, `PVC`, `NetworkPolicy` from memory in under 3 min each
- [ ] `kubeadm init` + join a worker on a fresh VM without referencing docs
- [ ] Diagnose a broken control-plane component from `journalctl`/`crictl`/`/var/log`
- [ ] Recover `etcd` from a snapshot
- [ ] Read & edit `/etc/kubernetes/manifests/*.yaml` confidently

Good luck. Discipline > intelligence here. Practice the boring things every day.
