# Portfolio Challenge 01: AI Cluster Pre-Flight & Readiness Auditor

## 🎯 Role & Scenario (The "Why" for Interviews)

You are a **Senior Platform / MLOps SRE**. Your organization is preparing to deploy high-cost LLM inference workloads (vLLM / OpenShift AI) onto an OpenShift cluster. 

Before any AI deployment pipeline runs—or before a maintenance window begins—your CI/CD pipeline must execute an automated **Pre-Flight Readiness & Audit Script** (`ai-cluster-preflight.sh`) and generate a structured **Cluster Audit Report** (`audit-report.txt`). If a cluster operator is degraded, a MachineConfigPool is mid-reboot, or an AI model image tag is mutable/unverified, the deployment must halt immediately.

By building this yourself, you will master **Objective 1 (Manage OpenShift Container Platform)** while creating a real-world SRE automation tool you can demo in technical interviews.

---

## 🛠️ Your Mission: What You Need to Build

Create a script named `ai-cluster-preflight.sh` (or a set of tested `oc` commands that you will assemble into a script) that performs **five automated checks** using **only native `oc` flags (`-o jsonpath`, `-o custom-columns`, `--field-selector`, `--sort-by`)**—avoid brittle `awk` or `sed` text scraping wherever `oc` has a native query mechanism.

### Requirement 1: Control Plane & Operator Gatekeeper
Query the cluster to print:
1. The current OpenShift desired version and active update channel from `clusterversion`.
2. Any `ClusterOperator` where the `Available` condition is **not** `True` OR the `Degraded` condition is **not** `False`.

### Requirement 2: Node & MachineConfigPool (MCP) Stability Check + GPU Readiness
1. Print all `MachineConfigPools` showing their `NAME`, `PAUSED` status (`.spec.paused`), and `UPDATING` condition status.
2. Query all cluster `Nodes` and output their `NAME`, `CPU` allocatable (`.status.allocatable.cpu`), `MEMORY` allocatable (`.status.allocatable.memory`), and whether they have an NVIDIA GPU label (`feature.node.kubernetes.io/pci-10de.present` or a custom label `accelerator=nvidia-gpu` that you can test with).

### Requirement 3: Immutable AI Model Image Pinning
In production AI platforms, deploying a container using a mutable tag (like `:latest` or `:1.2.0`) is a security and reproducibility risk; SREs pin workloads to an immutable `@sha256:...` digest.
1. Use an `oc` subcommand to inspect the remote image `quay.io/openshifttest/hello-openshift:1.2.0` **without** pulling it to your local disk or running a pod.
2. Extract its exact `sha256` manifest digest and its target CPU architecture (`amd64`/`arm64`).

### Requirement 4: Unhealthy Workload & Crash Hunter
1. Using `--field-selector` (not `grep`), list all Pods across all namespaces that are **neither** `Running` **nor** `Succeeded`.
2. Output them formatted strictly as: `NAMESPACE | POD_NAME | PHASE | NODE` using `-o custom-columns` or `-o jsonpath`.

### Requirement 5: Cluster Warning Event Stream
1. Query all `Warning` events across all namespaces, sorted chronologically by the timestamp of their most recent occurrence.

---

## 📚 Where to Research & What to Read (Official Docs & CLI Help)

On the real EX280 exam, your two best friends are `oc --help` / `oc explain` and the official OpenShift documentation. Use these exact sources to figure out your solution:

1. **Discovering JSONPath fields on any OpenShift resource (`oc explain`):**
   - Run `oc explain clusterversion.status` and `oc explain clusteroperator.status.conditions` in your terminal.
   - Run `oc explain node.status.allocatable` to see how CPU, memory, and extended resources (like GPUs) are structured.
2. **Mastering JSONPath filter expressions `[?(@.field=="value")]`:**
   - Read the Kubernetes/OpenShift JSONPath reference in the CLI docs:
     <https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/cli_tools/openshift-cli-oc>
   - *Tip to research:* How do you filter an array of conditions inside `jsonpath` so you only print the `.status` of the condition where `@.type=="Available"`?
3. **Inspecting container images via CLI:**
   - Run `oc image --help` and `oc image info --help` in your terminal.
   - Look at the `--output` / `-o` flags supported by `oc image info` and how `--filter-by-os` works when an image is a multi-architecture manifest list!
4. **Field Selectors on Pods and Events:**
   - Run `oc get pods --help | grep -A 5 field-selector` and test chaining multiple `!=` conditions separated by commas.

---

## ✅ Definition of Done (How We Will Validate Your Work)

Work through the 5 requirements at your own pace on your lab cluster (or dry-run them). 
- If you get stuck on a JSONPath filter, multi-arch image manifest error, or field selector syntax, **ask me for a hint** on that specific requirement.
- Once you have your commands or script ready, **paste your solution here**. I will review it as a Principal SRE & EX280 proctor, test edge cases with you, and help you polish it to commit into `platform-lab/01-cluster-diagnostics/`!
