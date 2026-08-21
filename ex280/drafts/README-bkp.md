# EX280 - Red Hat Certified System Administrator in OpenShift (~30-day study plan)


## 🎯 The 9 official EX280 objectives (current, OCP 4.18)

| # | Objective | File |
|---|-----------|------|
| 1 | Manage OpenShift Container Platform | [`01-manage-ocp.md`](objectives/01-manage-ocp.md) |
| 2 | Work with resource manifests | [`02-resource-manifests.md`](objectives/02-resource-manifests.md) |
| 3 | Deploy applications | [`03-deploy-applications.md`](objectives/03-deploy-applications.md) |
| 4 | Manage authentication and authorization | [`04-auth-and-authorization.md`](objectives/04-auth-and-authorization.md) |
| 5 | Configure network security | [`05-network-security.md`](./05-network-security.md) |
| 6 | Expose non-HTTP/SNI applications | [`06-expose-non-http-sni.md`](./06-expose-non-http-sni.md) |
| 7 | Enable developer self-service | [`07-developer-self-service.md`](./07-developer-self-service.md) |
| 8 | Manage OpenShift operators | [`08-openshift-operators.md`](objectives/08-openshift-operators.md) |
| 9 | Configure application security | [`09-application-security.md`](./09-application-security.md) |
| ★ | **Supplement: Storage (PV/PVC/SC)** - dropped from formal 4.18 objectives but still surfaces in stateful-app tasks | [`10-storage-supplement.md`](./10-storage-supplement.md) |

---

> **Target version: OpenShift Container Platform 4.18 (latest, released Dec 2025).**
> This repo is a merged & sorted curriculum derived from:
> - The [official Red Hat EX280 objectives page](https://www.redhat.com/en/services/training/red-hat-certified-openshift-administrator-exam)
> - The OCP 4.18 product documentation at <https://docs.redhat.com/en/documentation/openshift_container_platform/4.18>.

The repo is organized **by official exam objective** - one Markdown file per objective. Study the file, do the labs in your own cluster, take the weekly mock exam.

---

> Red Hat rule: **all configurations must persist after reboot without intervention.** Use `oc`/YAML - never edit files on nodes by hand.

> Note on storage: Red Hat removed "Provision persistent storage volumes and use storage classes" as a standalone objective when moving from EX280 v4.14 → v4.18. It now lives implicitly inside "Deploy applications" (stateful workloads) and "Work with resource manifests" (PVC YAML). The supplement chapter (`10-storage-supplement.md`) covers it so you can complete the mock-exam tasks that use PVCs (Postgres, Mongo, etc.).


## ⚠️ What changed vs. 4.14

Keep these 4.18 differences in mind:

| Topic | 4.14 behavior | 4.18 behavior |
|-------|---------------|---------------|
| `oc new-app` default workload | Could create `DeploymentConfig` from S2I | Creates a **`Deployment`** by default; `DeploymentConfig` is **deprecated** |
| Default OpenShift SDN | OpenShift SDN was still supported | **OVN-Kubernetes** is the **only** supported CNI (SDN removed in 4.17) |
| Pod Security | PSA admission active but warning-mostly | **Pod Security Admission (PSA)** enforces baseline & restricted profiles by default; pair PSA labels with SCC choices |
| Cluster updates | Console + CLI | Console + CLI + **EUS-to-EUS** updates and per-NodePool MCP pausing more prominent |
| Helm | Helm 3 (Cluster-scoped Helm Charts repo available) | Helm 3, native ProjectHelmChartRepository CRD |
| Image registry | image-registry operator | Same, but uses CSI snapshots for backup by default in many installs |

Always default to `Deployment` over `DeploymentConfig` on the exam unless a question explicitly asks for the latter.

---

## 📁 Repo structure

```
ex280-study-plan/
├── README.md                          ← you are here (curriculum + index)
├── 00-exam-overview.md                ← exam mechanics, scoring, doc strategy, tips
├── lab-setup.md                       ← CRC 2.x / Developer Sandbox / single-node 4.18
├── 01-manage-ocp.md                   ← Manage OpenShift Container Platform
├── 02-resource-manifests.md           ← Resource manifests + Kustomize
├── 03-deploy-applications.md          ← Templates, Helm, services, routes, scaling
├── 04-auth-and-authorization.md       ← HTPasswd, users, groups, RBAC
├── 05-network-security.md             ← Routes (TLS), NetworkPolicy, ingress
├── 06-expose-non-http-sni.md          ← LoadBalancer / NodePort / non-HTTP
├── 07-developer-self-service.md       ← Quotas, limit ranges, project templates
├── 08-openshift-operators.md          ← OLM, install/uninstall/delete operators
├── 09-application-security.md         ← SCCs, service accounts, secrets, jobs/cronjobs
├── 10-storage-supplement.md           ← PV/PVC/StorageClass (not formal v4.18 objective but still tested in practice)
├── cheatsheet.md                      ← One-page `oc` & YAML quick reference
├── resources.md                       ← Docs, videos, books, additional repos
└── mock-exams/
    ├── week1-mock.md                  ← 30 min, Obj 1–2
    ├── week2-mock.md                  ← 60 min, Obj 1–4
    ├── week3-mock.md                  ← 90 min, Obj 1–7
    ├── week4-mock.md                  ← 120 min, all objectives
    └── final-exam-3h.md               ← Full 3-hour exam simulation
```

## 📅 30-Day Plan (3–5 h/day ≈ 90–150 h total)

Each day has **Theory** (read & take notes), **Labs** (hands-on in your cluster), and a **Drill** (timed repetition without docs). Day 7/14/21/28/30 host the mock exams.

### Week 1 - Foundations, Cluster Ops, Manifests

| Day | Theme | Theory (~1 h) | Labs (~2 h) | Drill (~30 min) |
|-----|-------|---------------|-------------|------------------|
| 1 | **Lab setup + exam orientation** | Read `00-exam-overview.md` + `lab-setup.md`. Skim official objectives. | Install CRC 2.x **or** sign up for Red Hat Developer Sandbox (4.18). Verify `oc login`. | Run `oc api-resources`; explore `oc explain pod.spec.containers` |
| 2 | **Obj 1 - Cluster basics** | `01-manage-ocp.md` §1-4 (console, CLI, projects, images) | Lab 1.1-1.3 | Create / delete projects under 30 s |
| 3 | **Obj 1 - Observability + updates** | `01-manage-ocp.md` §5-9 (events, logs, troubleshooting, OCP updates) | Lab 1.4-1.6 | Tail pod logs; list cluster operators |
| 4 | **Obj 2 - Manifests intro** | `02-resource-manifests.md` §1-3 | Lab 2.1-2.2 | Write a Deployment YAML from scratch in 5 min |
| 5 | **Obj 2 - Kustomize, secrets, CMs** | `02-resource-manifests.md` §4-6 | Lab 2.3-2.4 | Build a base + overlay in 10 min |
| 6 | **Review + speed drills** | Re-read weak sections | Combine: deploy from YAML, edit, scale, expose | Generate any resource with `--dry-run=client -o yaml` |
| 7 | **🧪 Week 1 Mock Exam** | n/a | [`mock-exams/week1-mock.md`](./mock-exams/week1-mock.md) (30 min) + review | n/a |

### Week 2 — Application Deployment + Authentication

| Day | Theme | Theory (~1 h) | Labs (~2 h) | Drill (~30 min) |
|-----|-------|---------------|-------------|------------------|
| 8  | **Obj 3 – Deploy from images, templates, Helm** | `03-deploy-applications.md` §1–3 | Lab 3.1–3.2 | `oc new-app` 5 different ways |
| 9  | **Obj 3 – Services, routes, scaling + Storage supplement** | `03-deploy-applications.md` §4–6 + `10-storage-supplement.md` §1–4 | Lab 3.3–3.4 + Lab S.1 (PVC for Postgres) | Expose a service as HTTP route in 1 min; create a bound PVC in 2 min |
| 10 | **Obj 4 – HTPasswd identity provider** | `04-auth-and-authorization.md` §1–3 | Lab 4.1–4.2 (configure HTPasswd, add users) | Add a user, assign cluster-admin |
| 11 | **Obj 4 – Groups & RBAC** | `04-auth-and-authorization.md` §4–6 | Lab 4.3–4.4 | Bind a role to a group; verify with `oc auth can-i` |
| 12 | **Combined practice** | — | Re-do Lab 3.4 + Lab 4.3 back-to-back, no docs | — |
| 13 | **Review + fix gaps** | Re-read 03 & 04 trouble spots | Repeat any failed labs | — |
| 14 | **🧪 Week 2 Mock Exam** | — | [`mock-exams/week2-mock.md`](./mock-exams/week2-mock.md) (60 min) + review | — |

### Week 3 — Networking + Self-service

| Day | Theme | Theory (~1 h) | Labs (~2 h) | Drill (~30 min) |
|-----|-------|---------------|-------------|------------------|
| 15 | **Obj 5 – Routes & TLS termination** | `05-network-security.md` §1–3 | Lab 5.1 (edge) + 5.2 (passthrough) | Create edge / passthrough / re-encrypt from memory |
| 16 | **Obj 5 – NetworkPolicy & ingress** | `05-network-security.md` §4–6 | Lab 5.3 (deny-all + allow rules) | Write NetworkPolicy YAML in 5 min |
| 17 | **Obj 6 – Non-HTTP/SNI services** | `06-expose-non-http-sni.md` (all) | Lab 6.1–6.2 (NodePort + LoadBalancer) | Expose a TCP DB on a NodePort |
| 18 | **Obj 7 – Quotas & limit ranges** | `07-developer-self-service.md` §1–3 | Lab 7.1–7.2 | Apply ResourceQuota + LimitRange to a project |
| 19 | **Obj 7 – Project templates** | `07-developer-self-service.md` §4–5 | Lab 7.3 (custom project template) | Customize the project template & verify |
| 20 | **Cross-objective lab** | Re-skim `10-storage-supplement.md` if Day 9 felt rushed | "Onboard a new team": project template, quota, htpasswd users, group, route, NetworkPolicy, **PVC for a stateful app** | Lab S.3 (resize PVC) or S.4 (swap default SC) |
| 21 | **🧪 Week 3 Mock Exam** | — | [`mock-exams/week3-mock.md`](./mock-exams/week3-mock.md) (90 min) + review | — |

### Week 4 — Operators, App Security, Final Prep

| Day | Theme | Theory (~1 h) | Labs (~2 h) | Drill (~30 min) |
|-----|-------|---------------|-------------|------------------|
| 22 | **Obj 8 – OLM & operators** | `08-openshift-operators.md` (all) | Lab 8.1 (install via OperatorHub) + 8.2 (CLI install) | Install + uninstall an operator in 5 min |
| 23 | **Obj 9 – SCCs & service accounts** | `09-application-security.md` §1–3 | Lab 9.1–9.2 | Map a pod to `anyuid` SCC via SA |
| 24 | **Obj 9 – Secrets, jobs, cronjobs** | `09-application-security.md` §4–6 | Lab 9.3–9.4 | Write a CronJob YAML in 5 min |
| 25 | **🧪 Week 4 Mock Exam** | — | [`mock-exams/week4-mock.md`](./mock-exams/week4-mock.md) (120 min) + review | — |
| 26 | **Speed drills** | — | Repeat the 20 most common exam tasks; aim for ≤2 min each | — |
| 27 | **Targeted gaps day** | Re-read weak objectives | Redo any failed mock-exam tasks | — |
| 28 | **🧪 Final 3-h Mock Exam** | — | [`mock-exams/final-exam-3h.md`](./mock-exams/final-exam-3h.md) under exam conditions | — |
| 29 | **Post-mortem + targeted fixes** | Review every missed item | Retry the missed tasks until 100% | — |
| 30 | **Light review + rest** | Skim `cheatsheet.md` | Single end-to-end run-through, then stop early | Sleep well 😴 |

---

## ✅ How to use this repo

1. **Stand up your lab first.** Don't postpone this — see `lab-setup.md`. CRC 2.x runs OCP 4.18 on a laptop with 16 GB RAM.
2. **Read one objective file at a time.** Each ends with a "Drills" block — actually do them.
3. **Type every command yourself.** Muscle memory beats reading. Especially imperative `oc` commands with `--dry-run=client -o yaml`.
4. **At the exam you only get the official OpenShift docs at <https://docs.redhat.com>.** Practice navigating it now — `docs.redhat.com/en/documentation/openshift_container_platform/4.18`.
5. **Take every mock exam under exam conditions:** timer running, docs tab only, no Google, no AI.
6. **After each mock, journal what you missed** and add a row to the bottom of the relevant objective file in a "Gaps" section.

---

## 🎓 Passing score & exam logistics

- **Duration:** 3 hours, single section
- **Passing score:** 210 / 300 (70%)
- **Format:** Performance-based on a live OCP 4.18 cluster
- **Reference allowed:** Official OCP 4.18 documentation only — no internet, no notes
- **Persistence rule:** Everything must survive a node reboot

Good luck — see you on the other side of the cert. 🏅
