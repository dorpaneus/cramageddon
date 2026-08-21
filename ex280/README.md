# EX280 - Red Hat Certified System Administrator in OpenShift (Study Plan)

This repository is a consolidated study resource for the **EX280** exam, merging the official objectives with hands-on labs and OCP 4.18 documentation. Each objective file contains `.yaml` manifests, `oc` command cheatsheets, and step-by-step labs (each lab has a hidden worked solution).

> **🎯 Target version: OpenShift Container Platform 4.18 (GA late 2025).**
> Merged & sorted from:
> - The [official Red Hat EX280 objectives page](https://www.redhat.com/en/services/training/red-hat-certified-openshift-administrator-exam)
> - The OCP 4.18 product documentation at <https://docs.redhat.com/en/documentation/openshift_container_platform/4.18>
> - Community labs (`anishrana2001/Openshift`, `mgonzalezo/RedHat_ex280` - both authored for 4.14; every command here has been rewritten for **4.18**).

> **Red Hat rule:** all configurations must **persist after reboot** without intervention. Use `oc`/YAML - never edit files on nodes by hand.


> **Heads up**: These are my own personal study notes - not official, not affiliated with Red Hat, and no guarantees they're complete or error-free. Cross-check with the official docs and take it with a small pinch of salt. 🙂

---

## 🎯 1. Manage OpenShift Container Platform

*Goal: Master the CLI and web console, and run basic cluster health checks.*

**Theory** ([`01-manage-ocp.md`](01-manage-ocp.md)) - CLI & console · projects · images (tags/digests) · querying & filtering · import/export/edit · cluster status · logs & troubleshooting · monitoring · cluster updates

<details><summary>📋 Official objective coverage (Red Hat)</summary>

- [ ] Use the web console to manage and configure an OpenShift cluster
- [ ] Use the command-line interface to manage and configure an OpenShift cluster
- [ ] Create and delete projects
- [ ] Locate and examine container images
- [ ] Identify images using tags and digests
- [ ] Query, format, and filter attributes of Kubernetes resources
- [ ] Import, export, and configure Kubernetes resources
- [ ] Examine resources and cluster status
- [ ] Monitor cluster events and alerts
- [ ] View logs
- [ ] Assess the health of an OpenShift cluster
- [ ] Troubleshoot common container, pod, and cluster events and alerts
- [ ] Use product documentation
- [ ] Be prepared to perform all tasks of a Red Hat Certified Technologist in OpenShift

</details>

- [ ] **Lab 1.1:** [Project lifecycle](01-manage-ocp.md#lab-11--project-lifecycle-10-min)
- [ ] **Lab 1.2:** [Querying & filtering resources](01-manage-ocp.md#lab-12--querying--filtering-15-min)
- [ ] **Lab 1.3:** [Imperative → declarative](01-manage-ocp.md#lab-13--imperative--declarative-15-min)
- [ ] **Lab 1.4:** [Troubleshooting: break & fix](01-manage-ocp.md#lab-14--break--fix-25-min)
- [ ] **Lab 1.5:** [Cluster ops sweep](01-manage-ocp.md#lab-15--cluster-ops-sweep-20-min)
- [ ] **Lab 1.6:** [Cluster update dry-run (CRC)](01-manage-ocp.md#lab-16--cluster-update-dry-run-crc-15-min)
- **Key Commands:** `oc adm top nodes`, `oc describe`, `oc logs -f`, `oc get co`.

## ⚙️ 2. Work with Resource Manifests

*Goal: Move from ad-hoc commands to Infrastructure as Code.*

- [ ] **Lab 2.1:** [From scratch to running (YAML manifests)](02-resource-manifests.md#lab-21--from-scratch-to-running-20-min)
- [ ] **Lab 2.2:** [Patch storm - set/patch/rollout/label](02-resource-manifests.md#lab-22--patch-storm-15-min)
- [ ] **Lab 2.3:** [ConfigMap + Secret end-to-end](02-resource-manifests.md#lab-23--configmap--secret-end-to-end-25-min)
- [ ] **Lab 2.4:** [Kustomize bases and overlays](02-resource-manifests.md#lab-24--kustomize-base--2-overlays-40-min)
- **Key Commands:** `oc create ... --dry-run=client -o yaml`, `oc apply -k`, `oc set env`, `oc patch`.

## 📦 3. Deploy Applications (Templates & Helm)

*Goal: Automate deployments using standard packaging tools.*

- [ ] **Lab 3.1:** [Five flavors of `oc new-app`](03-deploy-applications.md#lab-31--five-flavors-of-new-app-25-min)
- [ ] **Lab 3.2:** [Author and process OpenShift Templates](03-deploy-applications.md#lab-32--author-and-use-a-template-25-min)
- [ ] **Lab 3.3:** [Service & Route end-to-end](03-deploy-applications.md#lab-33--service--route-end-to-end-20-min)
- [ ] **Lab 3.4:** [Installing and managing Helm charts](03-deploy-applications.md#lab-34--helm-install--values-25-min)
- **Key Commands:** `oc new-app`, `oc process`, `oc expose`, `helm install/upgrade/rollback`.

## 🔐 4. Manage Authentication and Authorization

*Goal: Secure the cluster and manage multi-tenancy.*

- [ ] **Lab 4.1:** [Configure HTPasswd identity provider + first user](04-auth-and-authorization.md#lab-41--configure-htpasswd--first-user-25-min)
- [ ] **Lab 4.2:** [Promote, demote, change password](04-auth-and-authorization.md#lab-42--promote-demote-change-password-15-min)
- [ ] **Lab 4.3:** [Groups + project-scoped RBAC](04-auth-and-authorization.md#lab-43--groups--project-scoped-roles-25-min)
- [ ] **Lab 4.4:** [Self-provisioning lockdown](04-auth-and-authorization.md#lab-44--self-provisioning-lockdown-15-min)
- **Key Commands:** `htpasswd -B`, `oc adm groups`, `oc adm policy add-role-to-group`, `oc auth can-i`.

## 🌐 5. Configure Network Security

*Goal: Control traffic flow into and within the cluster.*

- [ ] **Lab 5.1:** [Edge route with TLS + HTTP redirect](05-network-security.md#lab-51--edge-route-with-tls--http-redirect-25-min)
- [ ] **Lab 5.2:** [Passthrough route](05-network-security.md#lab-52--passthrough-route-25-min)
- [ ] **Lab 5.3:** [NetworkPolicy fortress (ingress/egress)](05-network-security.md#lab-53--networkpolicy-fortress-30-min)
- [ ] **Lab 5.4:** [Troubleshoot a 503](05-network-security.md#lab-54--troubleshoot-a-503-20-min)
- **Key Commands:** `oc create route edge/passthrough/reencrypt`, `oc get endpoints`, `oc apply -f networkpolicy.yaml`.

## 🛠️ 6. Expose Non-HTTP/SNI Applications

*Goal: Handle non-web traffic (e.g., databases).*

- [ ] **Lab 6.1:** [NodePort end-to-end](06-expose-non-http-sni.md#lab-61--nodeport-end-to-end-20-min)
- [ ] **Lab 6.2:** [Service type LoadBalancer (cloud/MetalLB)](06-expose-non-http-sni.md#lab-62--loadbalancer-cloud-or-metallb-only-20-min)
- [ ] **Lab 6.3:** [ExternalIP simulation on CRC](06-expose-non-http-sni.md#lab-63--externalip-simulation-on-crc-20-min)
- **Key Commands:** `oc expose --type=NodePort/LoadBalancer`, `oc patch svc`, `oc get svc -o wide`.

## ⚖️ 7. Enable Developer Self-Service

*Goal: Prevent resource exhaustion in a shared cluster.*

- [ ] **Lab 7.1:** [Quota that bites (ResourceQuota + LimitRange)](07-developer-self-service.md#lab-71--quota-that-bites-25-min)
- [ ] **Lab 7.2:** [ClusterResourceQuota by label](07-developer-self-service.md#lab-72--clusterresourcequota-by-label-20-min)
- [ ] **Lab 7.3:** [Customizing project templates](07-developer-self-service.md#lab-73--custom-project-template-35-min)
- [ ] **Lab 7.4:** [Hard block: ban NodePort for devs](07-developer-self-service.md#lab-74--hard-block-ban-nodeport-for-devs-15-min)
- **Key Commands:** `oc create quota`, `oc create limitrange`, `oc adm create-bootstrap-project-template`.

## 🤖 8. Manage OpenShift Operators

*Goal: Use the Operator Lifecycle Manager (OLM).*

- [ ] **Lab 8.1:** [Install an operator via the Console](08-openshift-operators.md#lab-81--install-via-console-15-min)
- [ ] **Lab 8.2:** [Install an operator via the CLI](08-openshift-operators.md#lab-82--install-via-cli-20-min)
- [ ] **Lab 8.3:** [Full uninstall + cleanup](08-openshift-operators.md#lab-83--full-uninstall--cleanup-15-min)
- [ ] **Lab 8.4:** [Manual approval drill (Subscriptions & CSVs)](08-openshift-operators.md#lab-84--manual-approval-drill-15-min)
- **Key Commands:** `oc get packagemanifests`, `oc get subscription/csv/installplan`, `oc apply -f subscription.yaml`.

## 🛡️ 9. Configure Application Security (SCC)

*Goal: Control pod permissions.*

- [ ] **Lab 9.1:** [SCC rescue mission](09-application-security.md#lab-91--scc-rescue-25-min)
- [ ] **Lab 9.2:** [Service Accounts and API access](09-application-security.md#lab-92--sa--api-access-20-min)
- [ ] **Lab 9.3:** [Job + Secret + ConfigMap](09-application-security.md#lab-93--job--secret--configmap-20-min)
- [ ] **Lab 9.4:** [CronJob with concurrency rules](09-application-security.md#lab-94--cronjob-with-concurrency-rules-20-min)
- **Key Commands:** `oc create sa`, `oc adm policy add-scc-to-user -z`, `oc create job/cronjob`, `oc create token`.

## 💾 ★ Supplement — Persistent Storage (PV / PVC / SC)

*Goal: Manage stateful workloads. Dropped as a standalone 4.18 objective, but still surfaces inside "Deploy applications" and "Resource manifests" tasks.*

- [ ] **Lab S.1:** [Dynamic provisioning with StorageClasses (PVC for Postgres)](10-storage-supplement.md#lab-s1--dynamic-pvc-for-postgres)
- [ ] **Lab S.2:** [Static PV with a manual StorageClass](10-storage-supplement.md#lab-s2--static-pv-with-manual-sc)
- [ ] **Lab S.3:** [Resize an existing PVC](10-storage-supplement.md#lab-s3--resize-an-existing-pvc)
- [ ] **Lab S.4:** [Swap the default StorageClass](10-storage-supplement.md#lab-s4--default-storageclass-swap)
- [ ] **Lab S.5:** [RWX shared volume](10-storage-supplement.md#lab-s5--rwx-shared-volume-only-if-your-lab-has-rwx-backend)
- **Key Commands:** `oc get sc/pv/pvc`, `oc set volume`, `oc patch pvc`, `oc get storageclass`.

> Red Hat removed "Provision persistent storage volumes and use storage classes" as a standalone objective moving from EX280 v4.14 → v4.18. The supplement chapter covers it so you can complete the mock-exam tasks that use PVCs (Postgres, Mongo, etc.).

---

## ⚠️ What changed vs. 4.14 (important if you're using older study repos)

When following the `anishrana2001` or `mgonzalezo` material (both 4.14), keep these 4.18 differences in mind:

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

## 📚 About the documentation links

Every objective file has a **🔗 Docs to bookmark** section at the bottom with links to the OCP 4.18 docs. All links resolve under the base URL:

```
https://docs.openshift.com/container-platform/4.18/
```

These are the same docs you'll have access to during the real EX280 exam (offline, in a browser tab). Open each link **before** exam day and pre-bookmark them in the browser you'll use, so you can navigate during the exam without searching.

If a specific page returns 404 (Red Hat occasionally renames pages between minor versions), drop the last path component and navigate from the section index — e.g., `…/applications/creating_applications.html` not found → go to `…/applications/index.html` and find it in the left-hand nav.

You can also browse the full HTML docs at the alternate base URL <https://docs.redhat.com/en/documentation/openshift_container_platform/4.18> (same content, different host).

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

## ✅ How to use this repo

1. **Stand up your lab first.** Don't postpone this — see `lab-setup.md`. CRC 2.x runs OCP 4.18 on a laptop with 16 GB RAM.
2. **Read one objective file at a time.** Each ends with labs (with hidden solutions) and a "Drills" block — actually do them.
3. **Type every command yourself.** Muscle memory beats reading. Especially imperative `oc` commands with `--dry-run=client -o yaml`.
4. **At the exam you only get the official OpenShift docs at <https://docs.redhat.com>.** Practice navigating it now — `docs.redhat.com/en/documentation/openshift_container_platform/4.18`.
5. **Take every mock exam under exam conditions:** timer running, docs tab only, no Google, no AI.
6. **After each mock, journal what you missed** and add a row to the bottom of the relevant objective file in a "Gaps" section.

---

## 🚀 Final Review Checklist

Before the exam, ensure you can:

1. Create a user, add them to a group, and give that group `admin` rights to a project.
2. Fix a broken deployment by checking logs and events.
3. Secure a route using a provided SSL certificate (edge / passthrough / re-encrypt).
4. Limit a project to only 5 pods and 2Gi of RAM with a ResourceQuota + LimitRange.
5. Install an operator from the CLI and confirm its CSV reaches `Succeeded`.
6. Grant a pod the least-permissive SCC it needs via a ServiceAccount.
7. Lock down self-provisioning and set a custom project-request message.
8. Deploy a stateful app backed by a dynamically-provisioned PVC that survives a pod delete.

---

## 🎓 Passing score & exam logistics

- **Duration:** 3 hours, single section
- **Passing score:** 210 / 300 (70%)
- **Format:** Performance-based on a live OCP 4.18 cluster
- **Reference allowed:** Official OCP 4.18 documentation only — no internet, no notes
- **Persistence rule:** Everything must survive a node reboot

---

**Credits & References:**
- [Official Red Hat EX280 Objectives](https://www.redhat.com/en/services/training/red-hat-certified-openshift-administrator-exam)
- [anishrana2001/Openshift](https://github.com/anishrana2001/Openshift)
- [mgonzalezo/RedHat_ex280](https://github.com/mgonzalezo/RedHat_ex280)

Good luck — see you on the other side of the cert. 🏅

— Maintainer notes: All `oc` examples and YAMLs target **OCP 4.18 / oc client 4.18+**. If you spot drift in a future minor release, file an issue.
