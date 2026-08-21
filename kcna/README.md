# KCNA 14-Day Study Curriculum

A structured, concept-first study plan for the **Kubernetes and Cloud Native Associate (KCNA)** certification, reinforced with hands-on labs and active-recall drills, and calibrated to the official CNCF / Linux Foundation domain weights.

---

## Exam at a Glance

| Item | Detail |
|---|---|
| Format | Online, proctored, multiple-choice |
| Questions | 60 |
| Duration | ~90 minutes |
| Passing score | 75% |
| Prerequisites | None |
| Style | Conceptual knowledge — *not* a hands-on performance exam |

**Recommended time investment:** 3–4 hours/day × 14 days (~42–56 focused hours). Comfortable for those with prior container/IT exposure; doable but tighter for complete beginners (use Days 6 and 14 as catch-up buffer).

---

## Domain Weight → Study Allocation

| Domain | Weight | Days Assigned |
|---|---|---|
| Kubernetes Fundamentals | 44% | Days 1–6 |
| Container Orchestration | 28% | Days 7–10 |
| Cloud Native Application Delivery | 16% | Days 11–12 |
| Cloud Native Architecture *(incl. Observability)* | 12% | Day 13 |
| Synthesis + Mock Exam | — | Day 14 |

> **Note:** In the current (post-Nov 2025) curriculum, Observability is no longer a standalone domain — it now lives inside Cloud Native Architecture, covered on Day 13.

---

## Daily Structure (repeats every day)

- **🌅 Morning Block — Concepts:** Mental models, architecture, and the relevant CNCF tools/projects.
- **⌨️ Midday Block — Hands-on:** `kubectl` commands, Minikube/Kind labs, and YAML manifest authoring.
- **🎯 Afternoon Block — Drills:** Self-check questions with collapsible answers.

---

## Table of Contents

| Day | Title | Primary Domain | Key Topics |
|----|------|----------------|-----------|
| **1** | Cloud Native & Containerization Foundations | Fundamentals (Containerization) | What "cloud native" means, containers vs VMs, OCI/runtimes, Docker basics, lab setup (kubectl + Minikube/Kind) |
| **2** | Kubernetes Architecture & Core Concepts | Fundamentals (Core Concepts) | Control plane (api-server, etcd, scheduler, controller-manager), worker nodes (kubelet, kube-proxy, runtime), first cluster |
| **3** | Pods & the Object Model | Fundamentals (Core Concepts) | Pods, labels/selectors, annotations, namespaces, declarative API, YAML manifest deep dive |
| **4** | Workload Controllers | Fundamentals (Core Concepts) | ReplicaSets, Deployments, rolling updates & rollbacks, DaemonSets, StatefulSets, Jobs, CronJobs |
| **5** | Scheduling | Fundamentals (Scheduling) | kube-scheduler flow, resource requests/limits, nodeSelector, affinity/anti-affinity, taints & tolerations |
| **6** | Administration & the API + Domain 1 Checkpoint | Fundamentals (Administration) | `kubectl` mastery, kubeconfig, API groups/versions, Helm & Kustomize intro, RBAC primer, mid-curriculum review |
| **7** | Kubernetes Networking | Orchestration (Networking) | Cluster networking model, CNI, Services (ClusterIP/NodePort/LoadBalancer), CoreDNS, Ingress, Gateway API |
| **8** | Storage | Orchestration (Storage) | Volumes, PV/PVC, StorageClasses, CSI, ephemeral vs persistent, ConfigMaps & Secrets |
| **9** | Security | Orchestration (Security) | RBAC deep dive, ServiceAccounts, Pod Security Standards/Admission, Secrets handling, NetworkPolicies, the 4 C's |
| **10** | Troubleshooting | Orchestration (Troubleshooting) | `logs` / `describe` / `exec` / `events`, probes (liveness/readiness/startup), CrashLoopBackOff, ImagePullBackOff, Pending |
| **11** | Application Delivery I | App Delivery | Delivery fundamentals, CI/CD pipelines, GitOps (Argo CD / Flux), declarative config, Helm/Kustomize packaging |
| **12** | Application Delivery II + Debugging | App Delivery (Debugging) | Deployment strategies (blue/green, canary, rolling), rollback flows, debugging delivery pipelines |
| **13** | Cloud Native Architecture & Observability | Architecture (incl. Observability) | Autoscaling (HPA/VPA/Cluster Autoscaler), serverless, service mesh, microservices, **Prometheus** + 3 pillars (metrics/logs/traces), OpenTelemetry, CNCF ecosystem, governance & community |
| **14** | Final Synthesis & Mock Exam | All domains | Weighted recall sweep, full-length timed practice exam, weak-area drilling, exam-day logistics |

---

## How to Use This Plan

1. Work the three blocks in order each day — concepts build the model, labs make it stick, drills expose gaps.
2. The labs are for *understanding*, not exam replication. If a day runs long, skim the lab and prioritize concepts + drills.
3. Days 6 and 14 double as buffer/catch-up if earlier days overran.
4. Treat the Day 14 mock as a real timed run, then re-drill your two weakest domains.

---

## Official References

- KCNA Certification page — *training.linuxfoundation.org/certification/kubernetes-cloud-native-associate/*
- KCNA Curriculum Overview & Candidate Handbook (linked from the certification page)
- CNCF Cloud Native Glossary & Landscape

---

## Progress Tracker

- [ ] Day 1 — Cloud Native & Containerization Foundations
- [ ] Day 2 — Kubernetes Architecture & Core Concepts
- [ ] Day 3 — Pods & the Object Model
- [ ] Day 4 — Workload Controllers
- [ ] Day 5 — Scheduling
- [ ] Day 6 — Administration & the API + Domain 1 Checkpoint
- [ ] Day 7 — Kubernetes Networking
- [ ] Day 8 — Storage
- [ ] Day 9 — Security
- [ ] Day 10 — Troubleshooting
- [ ] Day 11 — Application Delivery I
- [ ] Day 12 — Application Delivery II + Debugging
- [ ] Day 13 — Cloud Native Architecture & Observability
- [ ] Day 14 — Final Synthesis & Mock Exam
