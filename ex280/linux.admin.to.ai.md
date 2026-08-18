# From Linux Admin to AI/VM Platform Engineer on OpenShift

**A positioning and certification roadmap**
Compiled August 2026

---

## The core idea

> Stop describing yourself as an *OpenShift admin*. Become the person who **runs AI workloads and migrated VM estates on OpenShift**.
> Same clusters, very different market position.

The title "OpenShift administrator" is in slow decline. The skill set underneath it is not — it's being repriced. Demand is moving from "keeps clusters healthy" toward "runs AI and VM workloads on Kubernetes and is accountable when it breaks."

**Your Linux background is an asset, not baggage.** The migration wave specifically needs people who know hypervisor and OS internals well enough to map workloads, convert disk formats, repoint network policies, and validate that the application layer still works after the hypervisor changes underneath it. A cloud-native-only engineer cannot do that work. Don't discard the Linux identity — stack on top of it.

---

## Important: the certification program changed in May 2026

Most roadmaps you'll find online are stale. Red Hat rebuilt the entire program:

- Every certification now sits in one of **five tracks**: Enterprise Linux, Ansible, OpenShift, Cloud-native applications, and AI.
- Each track has up to **five progressive levels**: Technologist → Administrator/Developer → Engineer → Specialist → Architect.
- There is now a **track-specific RHCA** at the top of each track, rather than one generic RHCA.
- **Existing certifications were not invalidated.** Exam content, objectives, pricing, proctoring format, and the 3-year validity period are unchanged.
- The **AI track is the newest** and currently only goes as far as Administrator/Developer level.

---

## Certification sequence

### 1. EX280 — Red Hat Certified System Administrator in OpenShift *(next step, unchanged)*

- Performance-based, on OpenShift Container Platform 4.18.
- Configurations must persist after reboot without intervention — this is a Linux admin's exam.
- Table stakes. Gets you past HR and ATS filters.
- Prep: DO180 / DO280.

### 2. EX316 — OpenShift Virtualization *(fastest route to billable work)*

- Aimed at SREs, cluster engineers, sysadmins, and cloud engineers planning and implementing production-grade VMs under OpenShift. Based on OCP 4.18.
- The VMware-refugee market is live **right now**.
- Your Linux, storage, and networking instincts transfer directly.
- Prep: DO316 (+ DO256).

### 3. EX267 — Red Hat Certified Specialist in OpenShift AI *(the differentiator)*

- Tests deploying OpenShift AI and configuring it to build, deploy, and manage ML models. Based on RHOAI 2.25 and OCP 4.18.
- Covers: installing/configuring RHOAI, data science projects and workbenches, serving models with model-serving runtimes, monitoring for bias and drift, building data science pipelines.
- Prep: AI267.
- **Almost nobody with a Linux-ops background holds this. That is the point.**

### 4. EX380 — Advanced/Engineer level in OpenShift

- Prep: DO380 (recommended after EX280).

### 5. Then one specialist exam, flavour to taste

| Exam | Focus | Pick if… |
|---|---|---|
| **EX430** | Advanced Cluster Security (ACS) | you want the security/compliance angle |
| **EX432** | Advanced Cluster Management (ACM) | you want fleet/multi-cluster |
| **EX336** | Automating VM management with Ansible | you went deep on virtualization |
| **EX370** | OpenShift Data Foundation | storage is your organisation's pain |
| **EX229** | ROSA | your shop is AWS-heavy |

**Realistic timeline:** 2–3 years for the full program. The core is **EX280 + EX316 + EX267**. Everything else is optional depth.

---

## The bigger half: skills certs don't teach

EX267 teaches you the RHOAI console workflow. It will *not* teach you the things that make you expensive.

### AI / GPU platform

- NVIDIA GPU Operator, Node Feature Discovery
- MIG partitioning vs. time-slicing
- Driver / CUDA toolkit / kernel version management — genuinely painful, very Linux-admin-flavoured, which is exactly why it pays
- **vLLM** as a serving runtime; **KServe**; **llm-d** for distributed inference
- GPU quota and fair-share scheduling across teams; queueing (Kueue)
- Inference observability: tokens/sec, time-to-first-token, queue depth, GPU utilisation
- **Cost engineering.** Inference cost is now the dominant TCO variable — training happens once, serving happens millions or billions of times. Someone who cuts cost-per-million-tokens by 30% has an unarguable value story.

### VM migration

- Migration Toolkit for Virtualization (MTV) internals
- Storage mapping: ODF/Ceph, CSI, datastore translation
- Networking: Multus, NMState, SR-IOV
- Backup/DR: OADP/Velero, and meeting the same RTO/RPO as before
- **The hard part is organisational, and that's why it resists automation:** a migration toolkit can move disks and config, but it cannot prove that a commercial application vendor supports the new platform, or that the ops team can meet the same recovery objective. Being the person who runs *that* conversation is a career, not a task.

### Cross-cutting

- **GitOps** (Argo CD) and **Ansible** — declarative + automated is the operating model these platforms assume
- Prometheus / Grafana / Loki
- **OpenShift Lightspeed, MCP, and agentic-skills — from the operator angle.** What is an agent allowed to touch? Approval gates, reversibility, scoped RBAC, audit. This is the emerging job, not the thing replacing you.

---

## Build proof, not just badges

Certs get you screened in. Numbers get you hired. In a homelab or work sandbox:

- [ ] Single-node OpenShift (SNO) or OKD + one consumer GPU → serve a small open model with vLLM through KServe. Instrument it. **Publish the latency / throughput / cost numbers.**
- [ ] Migrate a handful of VMs from anything (Proxmox, plain KVM, vSphere) into OpenShift Virtualization using MTV — and **write up what broke.** The honest failure list is more credible than a success post.
- [ ] Wire Lightspeed or an MCP server into a cluster with scoped RBAC, and write about **what you didn't let it do.**

Three blog posts or GitHub repos on these topics will out-perform a fourth certificate.

---

## Rewrite how you describe yourself

Cheapest step in the whole strategy, and the one people skip. ~92% of organisations now use AI in hiring; it pattern-matches against the job description rather than evaluating potential. If your CV doesn't match the keywords, it never reaches a human. **Mirror the language of the postings you want.**

**Before:**
> OpenShift Administrator — managed clusters, patching, user access, troubleshooting.

**After:**
> Platform engineer (Linux/OpenShift) — run GPU-backed model serving for N teams; migrated N VMs off vSphere onto OpenShift Virtualization; reduced inference cost by X%.

Same clusters. Same person. Completely different search result.

---

## Sequencing over the next 24 months

**Near term (0–9 months)**
Pass EX280. Immediately volunteer for whatever VM migration or GPU-node work exists in your organisation — including the unglamorous parts. This is your credibility.

**Mid term (9–24 months)**
Add EX316 and EX267. Start being the person the AI/data teams come to when their models won't schedule.

**Longer term (24 months+)**
The specialisation is *"AI infrastructure engineer who happens to run it on OpenShift."* By then the OpenShift part is an implementation detail, not your identity.

---

## Two honest caveats

1. **Certs are a signal, not the substance.** Marginal value drops fast after the second or third. If you're ever choosing between another exam and six months of real GPU or migration work — **take the work.**
2. **Market forecasts are soft.** The migration-wave and AI-adoption numbers are solid. The 2029+ "agentic ops replaces admins" projections come largely from vendors and analysts with something to sell, and AI-displacement predictions have a poor accuracy record so far. Plan for the trend; don't bet the house on the timeline.

---

## Reference links

**Certifications**
- EX280 — https://www.redhat.com/en/services/training/red-hat-certified-openshift-administrator-exam
- EX316 — https://www.redhat.com/en/services/training/red-hat-certified-specialist-openshift-virtualization-ex316
- EX267 — https://www.redhat.com/en/services/training/ex267-red-hat-certified-specialist-openshift-ai
- OpenShift skills paths — https://www.redhat.com/en/resources/openshift-skill-paths-datasheet
- May 2026 program restructure (summary) — https://techbeatly.com/rhca/

**Platform / AI**
- OpenShift Lightspeed — https://www.redhat.com/en/technologies/cloud-computing/openshift/lightspeed
- OpenShift agentic-skills — https://github.com/openshift/agentic-skills
- OpenShift AI overview — https://www.redhat.com/en/resources/openshift-ai-overview

**Market context**
- Enterprises fleeing Broadcom → OpenShift Virtualization — https://www.techtarget.com/searchitoperations/news/366643085/Enterprises-fleeing-Broadcom-move-to-OpenShift-Virtualization
- VMware alternatives decision framework (2026) — https://digitalthoughtdisruption.com/2026/08/01/vmware-alternatives-enterprise-decision-framework-2026/
- Red Hat Summit 2026 AI announcements — https://www.redhat.com/en/blog/aws-and-red-hat-red-hat-summit-2026-accelerating-ai-innovation-and-open-source-infrastructure
