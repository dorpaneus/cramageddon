# EX280 - Red Hat Certified System Administrator in OpenShift (Study Plan)

This repository is a consolidated study resource for the **EX280** exam, merging the official objectives with hands-on labs and the OpenShift Container Platform (OCP) documentation. Each objective file contains `.yaml` manifests, `oc` command cheatsheets, and step-by-step labs (most with a hidden worked solution).

> **🎯 Version note**
> - The notes and labs were written against **OCP 4.18** (GA February 2025).
> - Red Hat's exam page now states the exam is based on **OCP 4.22**, and that **multiple exam versions are in use** at the same time. Check the Red Hat Learning Management System for the version you are booked on.
> - The objective list itself is unchanged between the two, so everything here still maps 1:1. See [What changed since 4.18](#what-changed) for the version-specific differences.
>
> Merged & sorted from:
> - The [official Red Hat EX280 objectives page](https://www.redhat.com/en/services/training/red-hat-certified-openshift-administrator-exam)
> - The OCP product documentation at <https://docs.redhat.com/en/documentation/openshift_container_platform/>
> - Community labs (`anishrana2001/Openshift`, `mgonzalezo/RedHat_ex280` - both authored for 4.14; commands here have been rewritten for 4.18+).

> **Red Hat rule:** all configurations must **persist and keep working** through the platform's normal lifecycle (including reboots) without manual intervention. Use `oc`/YAML - never edit files on nodes by hand.

> **Heads up**: These are my own personal study notes - not official, not affiliated with Red Hat, and no guarantees they're complete or error-free. Cross-check with the official docs and take it with a small pinch of salt. 🙂

---

## 🎯 1. Manage OpenShift Container Platform

*Goal: Master the CLI and web console, and run basic cluster health checks.*

**Theory** ([`01-manage-ocp.md`](objectives/01-manage-ocp.md)) - CLI & console · projects · images (tags/digests) · querying & filtering · import/export/edit · cluster status · logs & troubleshooting · monitoring · cluster updates (DO280 course content, not an exam objective)

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

- [ ] **Lab 1.1:** [Project lifecycle](objectives/01-manage-ocp.md#lab-11---project-lifecycle-10-min)
- [ ] **Lab 1.2:** [Querying & filtering resources](objectives/01-manage-ocp.md#lab-12---querying--filtering-15-min)
- [ ] **Lab 1.3:** [Imperative → declarative](objectives/01-manage-ocp.md#lab-13---imperative--declarative-15-min)
- [ ] **Lab 1.4:** [Troubleshooting: break & fix](objectives/01-manage-ocp.md#lab-14---break--fix-25-min)
- [ ] **Lab 1.5:** [Cluster ops sweep](objectives/01-manage-ocp.md#lab-15---cluster-ops-sweep-20-min)
- [ ] **Lab 1.6:** [Cluster update dry-run (CRC)](objectives/01-manage-ocp.md#lab-16---cluster-update-dry-run-crc-15-min)
- **Key Commands:** `oc adm top nodes`, `oc describe`, `oc logs -f`, `oc get co`.

## ⚙️ 2. Work with Resource Manifests

*Goal: Move from ad-hoc commands to Infrastructure as Code.*

**Theory** ([`02-resource-manifests.md`](objectives/02-resource-manifests.md)) - YAML anatomy · updating deployments · ConfigMaps · Secrets · Kustomize basics · Kustomize overlays

<details><summary>📋 Official objective coverage (Red Hat)</summary>

- [ ] Deploy applications from YAML resource manifests
- [ ] Update application deployments
- [ ] Deploy applications using Kustomize
- [ ] Work with Kustomize overlays
- [ ] Create and use secrets
- [ ] Create and use configuration maps

</details>

- [ ] **Lab 2.1:** [From scratch to running (YAML manifests)](objectives/02-resource-manifests.md#lab-21--from-scratch-to-running-20-min)
- [ ] **Lab 2.2:** [Patch storm - set/patch/rollout/label](objectives/02-resource-manifests.md#lab-22--patch-storm-15-min)
- [ ] **Lab 2.3:** [ConfigMap + Secret end-to-end](objectives/02-resource-manifests.md#lab-23--configmap--secret-end-to-end-25-min)
- [ ] **Lab 2.4:** [Kustomize bases and overlays](objectives/02-resource-manifests.md#lab-24--kustomize-base--2-overlays-40-min)
- **Key Commands:** `oc create ... --dry-run=client -o yaml`, `oc apply -k`, `oc set env`, `oc patch`.

## 📦 3. Deploy Applications (Templates & Helm)

*Goal: Automate deployments using standard packaging tools.*

**Theory** ([`03-deploy-applications.md`](objectives/03-deploy-applications.md)) - `oc new-app` · templates · Helm · Deployments, ReplicaSets, labels & selectors · services · routes

<details><summary>📋 Official objective coverage (Red Hat)</summary>

- [ ] Deploy applications from templates and Helm charts
- [ ] Manage application deployments
- [ ] Work with replica sets
- [ ] Work with labels and selectors
- [ ] Configure services
- [ ] Expose applications to external access

</details>

- [ ] **Lab 3.1:** [Five flavors of `oc new-app`](objectives/03-deploy-applications.md#lab-31---five-flavors-of-new-app-25-min)
- [ ] **Lab 3.2:** [Author and process OpenShift Templates](objectives/03-deploy-applications.md#lab-32---author-and-use-a-template-25-min)
- [ ] **Lab 3.3:** [Service & Route end-to-end](objectives/03-deploy-applications.md#lab-33---service--route-end-to-end-20-min)
- [ ] **Lab 3.4:** [Installing and managing Helm charts](objectives/03-deploy-applications.md#lab-34---helm-install--values-25-min)
- **Key Commands:** `oc new-app`, `oc process`, `oc expose`, `helm install/upgrade/rollback`.

## 🔐 4. Manage Authentication and Authorization

*Goal: Secure the cluster and manage multi-tenancy.*

**Theory** ([`04-auth-and-authorization.md`](objectives/04-auth-and-authorization.md)) - OAuth & identity providers · HTPasswd · users & identities · groups · RBAC · self-provisioning

<details><summary>📋 Official objective coverage (Red Hat)</summary>

- [ ] Configure the HTPasswd identity provider for authentication
- [ ] Create and delete users
- [ ] Modify user passwords
- [ ] Create and manage groups
- [ ] Modify user and group permissions

</details>

- [ ] **Lab 4.1:** [Configure HTPasswd identity provider + first user](objectives/04-auth-and-authorization.md#lab-41---configure-htpasswd--first-user-25-min)
- [ ] **Lab 4.2:** [Promote, demote, change password](objectives/04-auth-and-authorization.md#lab-42---promote-demote-change-password-15-min)
- [ ] **Lab 4.3:** [Groups + project-scoped RBAC](objectives/04-auth-and-authorization.md#lab-43---groups--project-scoped-roles-25-min)
- [ ] **Lab 4.4:** [Self-provisioning lockdown](objectives/04-auth-and-authorization.md#lab-44---self-provisioning-lockdown-15-min)
- **Key Commands:** `htpasswd -B`, `oc set data secret/...`, `oc adm groups`, `oc adm policy add-role-to-group`, `oc auth can-i`.

## 🌐 5. Configure Network Security

*Goal: Control traffic flow into and within the cluster.*

**Theory** ([`05-network-security.md`](objectives/05-network-security.md)) - networking stack · routes · TLS (edge / passthrough / re-encrypt) · NetworkPolicy · IngressController · internal TLS (service serving certificates) · SDN troubleshooting

<details><summary>📋 Official objective coverage (Red Hat)</summary>

- [ ] Configure networking components
- [ ] Troubleshoot software defined networking
- [ ] Create and edit external routes
- [ ] Control cluster network ingress
- [ ] Secure external and internal traffic using TLS certificates
- [ ] Configure application network policies

</details>

- [ ] **Lab 5.1:** [Edge route with TLS + HTTP redirect](objectives/05-network-security.md#lab-51--edge-route-with-tls--http-redirect-25-min)
- [ ] **Lab 5.2:** [Passthrough route](objectives/05-network-security.md#lab-52--passthrough-route-25-min)
- [ ] **Lab 5.3:** [NetworkPolicy fortress (ingress/egress)](objectives/05-network-security.md#lab-53--networkpolicy-fortress-30-min)
- [ ] **Lab 5.4:** [Troubleshoot a 503](objectives/05-network-security.md#lab-54--troubleshoot-a-503-20-min)
- [ ] **Lab 5.5:** [Internal TLS with service serving certificates](objectives/05-network-security.md#lab-55--internal-tls-with-service-serving-certificates-25-min)
- **Key Commands:** `oc create route edge/passthrough/reencrypt`, `oc get endpointslices`, `oc apply -f networkpolicy.yaml`, `oc annotate service … service.beta.openshift.io/serving-cert-secret-name=…`.

## 🛠️ 6. Expose Non-HTTP/SNI Applications

*Goal: Handle non-web traffic (e.g., databases).*

**Theory** ([`06-expose-non-http-sni.md`](objectives/06-expose-non-http-sni.md)) - NodePort · LoadBalancer (cloud / MetalLB) · ExternalIP

<details><summary>📋 Official objective coverage (Red Hat)</summary>

- [ ] Configure a load balancer service
- [ ] Configure external application access

</details>

- [ ] **Lab 6.1:** [NodePort end-to-end](objectives/06-expose-non-http-sni.md#lab-61--nodeport-end-to-end-20-min)
- [ ] **Lab 6.2:** [Service type LoadBalancer (cloud/MetalLB)](objectives/06-expose-non-http-sni.md#lab-62--loadbalancer-cloud-or-metallb-only-20-min)
- [ ] **Lab 6.3:** [ExternalIP simulation on CRC](objectives/06-expose-non-http-sni.md#lab-63--externalip-simulation-on-crc-20-min)
- **Key Commands:** `oc expose --type=NodePort/LoadBalancer`, `oc patch svc`, `oc get svc -o wide`.

## ⚖️ 7. Enable Developer Self-Service

*Goal: Prevent resource exhaustion in a shared cluster.*

**Theory** ([`07-developer-self-service.md`](objectives/07-developer-self-service.md)) - ResourceQuota · LimitRange · quota scopes · ClusterResourceQuota · project templates

<details><summary>📋 Official objective coverage (Red Hat)</summary>

- [ ] Configure cluster resource quotas
- [ ] Configure project quotas
- [ ] Configure project resource requirements
- [ ] Configure project limit ranges
- [ ] Configure project templates

</details>

- [ ] **Lab 7.1:** [Quota that bites (ResourceQuota + LimitRange)](objectives/07-developer-self-service.md#lab-71--quota-that-bites-25-min)
- [ ] **Lab 7.2:** [ClusterResourceQuota by label](objectives/07-developer-self-service.md#lab-72--clusterresourcequota-by-label-20-min)
- [ ] **Lab 7.3:** [Customizing project templates](objectives/07-developer-self-service.md#lab-73--custom-project-template-35-min)
- [ ] **Lab 7.4:** [Hard block: ban NodePort for devs](objectives/07-developer-self-service.md#lab-74--hard-block-ban-nodeport-for-devs-15-min)
- **Key Commands:** `oc create quota`, `oc create limitrange`, `oc adm create-bootstrap-project-template`.

## 🤖 8. Manage OpenShift Operators

*Goal: Use the Operator Lifecycle Manager (OLM).*

**Theory** ([`08-openshift-operators.md`](objectives/08-openshift-operators.md)) - OLM model · OperatorGroups · console & CLI install · manual approval · uninstall & full cleanup · catalog sources

<details><summary>📋 Official objective coverage (Red Hat)</summary>

- [ ] Install an operator
- [ ] Uninstall an operator
- [ ] Delete an operator

</details>

- [ ] **Lab 8.1:** [Install an operator via the Console](objectives/08-openshift-operators.md#lab-81--install-via-console-15-min)
- [ ] **Lab 8.2:** [Install an operator via the CLI](objectives/08-openshift-operators.md#lab-82--install-via-cli-20-min)
- [ ] **Lab 8.3:** [Full uninstall + cleanup](objectives/08-openshift-operators.md#lab-83--full-uninstall--cleanup-15-min)
- [ ] **Lab 8.4:** [Manual approval drill (Subscriptions & CSVs)](objectives/08-openshift-operators.md#lab-84--manual-approval-drill-15-min)
- **Key Commands:** `oc get packagemanifests`, `oc get subscription/csv/installplan`, `oc apply -f subscription.yaml`.

## 🛡️ 9. Configure Application Security (SCC)

*Goal: Control pod permissions.*

**Theory** ([`09-application-security.md`](objectives/09-application-security.md)) - service accounts · SCCs · Pod Security Admission · privileged workloads · secrets · Jobs · CronJobs

<details><summary>📋 Official objective coverage (Red Hat)</summary>

- [ ] Configure and manage service accounts
- [ ] Run privileged applications
- [ ] Manage and apply permissions using security context constraints
- [ ] Create and apply secrets to manage sensitive information
- [ ] Configure application access to Kubernetes APIs
- [ ] Deploy jobs to perform one-time tasks
- [ ] Configure Kubernetes cron jobs

</details>

- [ ] **Lab 9.1:** [SCC rescue mission](objectives/09-application-security.md#lab-91--scc-rescue-25-min)
- [ ] **Lab 9.2:** [Service Accounts and API access](objectives/09-application-security.md#lab-92--sa--api-access-20-min)
- [ ] **Lab 9.3:** [Job + Secret + ConfigMap](objectives/09-application-security.md#lab-93--job--secret--configmap-20-min)
- [ ] **Lab 9.4:** [CronJob with concurrency rules](objectives/09-application-security.md#lab-94--cronjob-with-concurrency-rules-20-min)
- **Key Commands:** `oc create sa`, `oc adm policy add-scc-to-user -z`, `oc create job/cronjob`, `oc create token`.

## 💾 ★ Supplement — Persistent Storage (PV / PVC / SC)

*Goal: Manage stateful workloads. Not a standalone objective on the current exam, but stateful apps still need PVCs.*

**Theory** ([`10-storage-supplement.md`](objectives/10-storage-supplement.md)) - access modes · reclaim policy · dynamic & static provisioning · binding modes · resizing · StatefulSets · troubleshooting

- [ ] **Lab S.1:** [Dynamic provisioning with StorageClasses (PVC for Postgres)](objectives/10-storage-supplement.md#lab-s1--dynamic-pvc-for-postgres)
- [ ] **Lab S.2:** [Static PV with a manual StorageClass](objectives/10-storage-supplement.md#lab-s2--static-pv-with-manual-sc)
- [ ] **Lab S.3:** [Resize an existing PVC](objectives/10-storage-supplement.md#lab-s3--resize-an-existing-pvc)
- [ ] **Lab S.4:** [Swap the default StorageClass](objectives/10-storage-supplement.md#lab-s4--default-storageclass-swap)
- [ ] **Lab S.5:** [RWX shared volume](objectives/10-storage-supplement.md#lab-s5--rwx-shared-volume-only-if-your-lab-has-rwx-backend)
- **Key Commands:** `oc get sc/pv/pvc`, `oc set volume`, `oc patch pvc`, `oc get storageclass`.

> "Provision persistent storage volumes and use storage classes" appeared in the older (4.14-based) objective list but is not in the current one. This supplement covers it so you can complete tasks that need a PVC (Postgres, MySQL, etc.).

---

<a id="what-changed"></a>

## ⚠️ What changed since 4.18 (and vs 4.14)

If you're following the `anishrana2001` or `mgonzalezo` material (both 4.14), or sitting a newer exam version, keep these differences in mind:

| Topic | Older behavior | Current behavior |
|-------|----------------|------------------|
| Workload type | `DeploymentConfig` common in 4.x material | `DeploymentConfig` is **deprecated** (since 4.14); `oc new-app` creates a **`Deployment`** |
| Cluster network | OpenShift SDN still available in 4.14 | **OVN-Kubernetes** is the only CNI (SDN removed in 4.17) |
| Pod Security | — | **SCC is the gate that admits or rejects pods.** Pod Security Admission runs alongside it: global enforce stays `privileged`, and OpenShift's label syncer sets each user namespace's `warn`/`audit` labels from the SCCs its service accounts can use. "would violate PodSecurity" messages are usually warnings, not rejections |
| Service endpoints | `oc get endpoints` | The Endpoints API is **deprecated** from Kubernetes 1.33 (OCP 4.20) and prints a warning; use `oc get endpointslices -l kubernetes.io/service-name=<svc>` |
| Web console | Separate Administrator and Developer perspectives; *Operators → OperatorHub* | The Developer perspective is **off by default from 4.19**; newer consoles call OperatorHub the **Software Catalog** |
| Helm | Helm 3, `HelmChartRepository` / `ProjectHelmChartRepository` CRDs | Same |
| Community images | `docker.io/bitnami/*` widely used in labs | The free Bitnami catalog was **archived in Sept 2025** — prefer Red Hat / UBI / `quay.io/sclorg` images |

Always default to `Deployment` over `DeploymentConfig` on the exam unless a question explicitly asks for the latter.

---

## 📚 About the documentation links

Every objective file has a **🔗 Docs to bookmark** section at the bottom, pointing at the 4.18 docs (links checked October 2026). OpenShift docs moved to **docs.redhat.com** on March 12, 2025. Old `docs.openshift.com` links are unreliable: since 4.18 several guides were split (networking became *Ingress and load balancing*, *Network security*, *Networking Operators*, …), so old paths often don't map to a current page. Use this base URL, swapping in your exam's version:

```
https://docs.redhat.com/en/documentation/openshift_container_platform/<version>/
```

During the exam you get the product documentation in a browser, with no other internet access. Practice navigating it **before** exam day so you can find pages without searching.

If a specific page returns 404 (Red Hat occasionally renames pages between minor versions), go up to the guide's index page and use the left-hand navigation. For example, go to `…/html/building_applications/index` and find the page in the nav.

---

## 📁 Repo structure

```
ex280/
├── README.md                          ← you are here (curriculum + index)
├── LICENSE
├── objectives/
│   ├── 01-manage-ocp.md               ← Manage OpenShift Container Platform
│   ├── 02-resource-manifests.md       ← Resource manifests + Kustomize
│   ├── 03-deploy-applications.md      ← Templates, Helm, services, routes, scaling
│   ├── 04-auth-and-authorization.md   ← HTPasswd, users, groups, RBAC
│   ├── 05-network-security.md         ← Routes (TLS), NetworkPolicy, ingress
│   ├── 06-expose-non-http-sni.md      ← LoadBalancer / NodePort / ExternalIP
│   ├── 07-developer-self-service.md   ← Quotas, limit ranges, project templates
│   ├── 08-openshift-operators.md      ← OLM, install/uninstall/delete operators
│   ├── 09-application-security.md     ← SCCs, service accounts, secrets, jobs/cronjobs
│   └── 10-storage-supplement.md       ← PV/PVC/StorageClass (supplement, not a current objective)
├── mock-exams/
│   └── week1-mock.md                  ← 30 min, Obj 1–2
└── drafts/                            ← work in progress, not part of the study path
```

*Planned:* exam overview, lab setup guide, one-page cheatsheet, resources list, mock exams for weeks 2–4 and a full 3-hour final.

## ✅ How to use this repo

1. **Stand up your lab first.** Don't postpone this. Options: OpenShift Local (CRC) on a laptop with 16 GB+ RAM, a single-node cluster, or the Developer Sandbox (no cluster-admin, so many labs won't work there).
2. **Read one objective file at a time.** Each ends with labs (most with hidden solutions) and a "Drills" block — actually do them.
3. **Type every command yourself.** Muscle memory beats reading. Especially imperative `oc` commands with `--dry-run=client -o yaml`.
4. **At the exam you only get the official OpenShift docs.** Practice navigating <https://docs.redhat.com/en/documentation/openshift_container_platform/> now.
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

- **Duration:** 3 hours
- **Passing score:** 210 / 300 (70%)
- **Format:** Hands-on, performance-based on a live OpenShift cluster; no multiple-choice questions
- **Version:** based on OCP 4.22 per Red Hat's exam page; multiple versions are in use, so check your booking
- **Reference allowed:** Official product documentation only — no internet, no notes
- **Persistence rule:** Everything must keep working without manual intervention, including after a reboot
- **Results:** emailed, usually within 3 U.S. business days; only the total score is reported

---

**Credits & References:**
- [Official Red Hat EX280 Objectives](https://www.redhat.com/en/services/training/red-hat-certified-openshift-administrator-exam)
- [OpenShift Container Platform documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/)
- [anishrana2001/Openshift](https://github.com/anishrana2001/Openshift)
- [mgonzalezo/RedHat_ex280](https://github.com/mgonzalezo/RedHat_ex280)

Good luck — see you on the other side of the cert. 🏅

— Maintainer notes: `oc` examples and YAMLs were written for **OCP 4.18 / oc client 4.18+** and are being reviewed against newer releases. If you spot drift, file an issue.
