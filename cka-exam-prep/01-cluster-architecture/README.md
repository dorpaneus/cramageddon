# Domain 1 — Cluster Architecture, Installation & Configuration (25%)

> Foundation of the exam. If your cluster install or RBAC understanding is shaky, everything else falls apart.

## Official objectives (CNCF v1.35)

| # | Objective | File |
| - | --- | --- |
| 1.1 | Manage role based access control (RBAC) | [`01-rbac.md`](./01-rbac.md) |
| 1.2 | Prepare underlying infrastructure for installing a Kubernetes cluster | [`02-infrastructure-prep.md`](./02-infrastructure-prep.md) |
| 1.3 | Create and manage Kubernetes clusters using kubeadm | [`03-kubeadm-cluster.md`](./03-kubeadm-cluster.md) |
| 1.4 | Manage the lifecycle of Kubernetes clusters | [`04-cluster-lifecycle.md`](./04-cluster-lifecycle.md) |
| 1.5 | Implement and configure a highly-available control plane | [`05-ha-control-plane.md`](./05-ha-control-plane.md) |
| 1.6 | Use Helm and Kustomize to install cluster components | [`06-helm-kustomize.md`](./06-helm-kustomize.md) |
| 1.7 | Understand extension interfaces (CNI, CSI, CRI, etc.) | [`07-extension-interfaces.md`](./07-extension-interfaces.md) |
| 1.8 | Understand CRDs, install and configure operators | [`08-crds-operators.md`](./08-crds-operators.md) |

## Exam frequency notes

- RBAC questions: **almost always** at least one. Often "create a SA with X permissions, bind it, verify."
- kubeadm cluster upgrade: classic **7%** question; takes 10–15 min if practiced, 30+ if not.
- etcd backup/restore: **very common** (~5–7%). Memorize the exact `etcdctl` syntax.
- Helm install / Kustomize apply: **new and common** since 2025 refresh.
- CRDs / Operators: **new** — usually "install this Operator, then verify the CRD it created."

## Study tips

- Practice `kubeadm` on **real VMs**, not just kind. The exam uses real VMs.
- Practice etcd backup/restore until you can do it without docs — most people fail here under time pressure.
- For RBAC, learn `kubectl auth can-i` as your reflexive verifier.
- Helm and Kustomize are simple in concept but require knowing the **CLI surface**. Practice `helm install/upgrade/rollback/uninstall` and `kubectl apply -k`.
