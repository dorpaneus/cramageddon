# Domain 2 — Workloads & Scheduling (15%)

> Day-to-day developer-adjacent work: Deployments, scaling, config, scheduling decisions.

## Official objectives (CNCF v1.35)

| # | Objective | File |
| - | --- | --- |
| 2.1 | Understand deployments and how to perform rolling update and rollbacks | [`01-deployments-rollouts.md`](./01-deployments-rollouts.md) |
| 2.2 | Use ConfigMaps and Secrets to configure applications | [`02-configmaps-secrets.md`](./02-configmaps-secrets.md) |
| 2.3 | Configure workload autoscaling | [`03-autoscaling.md`](./03-autoscaling.md) |
| 2.4 | Understand the primitives used to create robust, self-healing, application deployments | [`04-self-healing.md`](./04-self-healing.md) |
| 2.5 | Configure Pod admission and scheduling (limits, node affinity, etc.) | [`05-pod-scheduling.md`](./05-pod-scheduling.md) |

## Exam frequency notes

- Deployments + rolling updates: **most common topic** in this domain
- ConfigMaps/Secrets as env/volume/envFrom: 1-2 tasks expected
- HPA: 1 task expected
- Scheduling (nodeSelector, taints, affinity): 1-2 tasks, often subtle
- Self-healing (probes): often a "fix this probe" troubleshoot task

## Study tip

**Speed matters most here.** These are short tasks. Practice writing each YAML from memory under 90 seconds. The exam will reward muscle memory.
