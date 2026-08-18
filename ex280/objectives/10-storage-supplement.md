# Supplement: Storage (PV / PVC / StorageClass)

**Status:** Not a standalone objective in EX280 v4.18 (it was in v4.14). Storage was folded into "Deploy applications" and "Manage resource manifests" in the 4.18 revision. You will still encounter storage in practice — stateful apps (databases, queues, image registries) require PVCs, and several mocks in this repo use them.

Treat this chapter as **required reading**. Estimated time: 3 hours.

---

## Why this matters even if it's not on the objectives list

A real exam task like "deploy PostgreSQL with persistent data" implicitly tests:
- PVC creation (or template parameter).
- Default StorageClass behavior.
- ConfigMap / Secret mounting alongside the volume.
- Verifying the pod runs *and* data persists after pod deletion.

Skipping this means you can't complete those tasks. Don't skip.

---

## The four storage objects

| Object | Purpose | Who creates it |
|--------|---------|----------------|
| `PersistentVolume` (PV) | Cluster-wide piece of storage (the actual disk/backend). | Admin (static) or dynamically by StorageClass |
| `PersistentVolumeClaim` (PVC) | A pod's request: "I need X GiB with these access modes." | User / app YAML |
| `StorageClass` | A recipe for dynamic provisioning (which backend, parameters). | Admin once per cluster |
| `VolumeAttachment` / `CSIDriver` | Implementation details; you usually don't touch them. | Operator |

The flow:

```
Pod → PVC (request) → matched against PV (or StorageClass dynamically provisions one) → mounted into the container at the path you specify.
```

---

## Access modes (memorize these)

| Mode | Abbrev | Meaning |
|------|--------|---------|
| ReadWriteOnce | RWO | One node can mount r/w. Most common. Block & file. |
| ReadOnlyMany | ROX | Many nodes can mount read-only. |
| ReadWriteMany | RWX | Many nodes can mount r/w. Usually NFS / CephFS / EFS. |
| ReadWriteOncePod | RWOP | Single pod r/w (4.x+). Stronger than RWO. |

Most cloud block storage (EBS, GCE PD, Azure Disk) is **RWO only**. File-based (NFS, EFS, CephFS) supports **RWX**.

---

## Reclaim policy

What happens to the PV when the PVC is deleted:

| Policy | Behavior |
|--------|----------|
| `Delete` | PV and underlying storage are destroyed (cloud disks deleted). Default for dynamic provisioning. |
| `Retain` | PV stays in `Released` state; admin must clean up manually. Safer for prod data. |
| `Recycle` | Deprecated. Don't use. |

Change a PV's reclaim policy after creation:

```bash
oc patch pv pv-name -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
```

---

## Inspect the cluster's storage capability

```bash
oc get storageclass
oc get sc                                  # short form
oc get pv
oc get pvc -A                              # cluster-wide claims
oc describe sc <name>                      # see provisioner + parameters
oc get sc -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}'
# → prints the default SC name
```

Default StorageClass — exactly one SC should have the annotation:

```
storageclass.kubernetes.io/is-default-class: "true"
```

Set / unset default:

```bash
oc patch storageclass gp3-csi -p \
  '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

oc patch storageclass old-default -p \
  '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
```

---

## Dynamic provisioning (the common case)

A PVC referencing a StorageClass (or omitting `storageClassName` to use the default) causes the SC's provisioner to create a PV automatically.

### Minimal PVC

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data
  namespace: myapp
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 2Gi
  # storageClassName omitted → use cluster default
```

```bash
oc apply -f pvc.yaml
oc get pvc data -n myapp
# NAME   STATUS   VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS
# data   Bound    pvc-...  2Gi        RWO            gp3-csi
```

### PVC referencing a specific SC

```yaml
spec:
  storageClassName: gp3-csi
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 5Gi
```

### PVC for RWX (shared storage)

```yaml
spec:
  storageClassName: ocs-storagecluster-cephfs   # or nfs-csi, efs-sc, etc.
  accessModes: [ReadWriteMany]
  resources:
    requests:
      storage: 10Gi
```

---

## Mounting a PVC into a Pod

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: db
spec:
  replicas: 1
  selector: {matchLabels: {app: db}}
  template:
    metadata: {labels: {app: db}}
    spec:
      containers:
      - name: db
        image: quay.io/sclorg/postgresql-15-c9s:latest
        env:
        - {name: POSTGRESQL_USER, value: app}
        - {name: POSTGRESQL_PASSWORD, value: secret}
        - {name: POSTGRESQL_DATABASE, value: appdb}
        ports:
        - {containerPort: 5432}
        volumeMounts:
        - name: data
          mountPath: /var/lib/pgsql/data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: db-data
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: db-data
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests: {storage: 2Gi}
```

**Verify persistence:**

```bash
# Write data
oc exec deploy/db -- psql -U app -d appdb -c "CREATE TABLE t (id int); INSERT INTO t VALUES (42);"

# Delete the pod (PVC stays)
oc delete pod -l app=db

# After the new pod comes up, data should still be there
oc exec deploy/db -- psql -U app -d appdb -c "SELECT * FROM t;"
# id
# ----
#  42
```

---

## Static provisioning (rarer, but possible on exam)

Admin pre-creates a PV; users claim it.

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: local-pv-01
spec:
  capacity: {storage: 5Gi}
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual              # custom SC name (no provisioner needed)
  hostPath:                              # for lab only — never in prod
    path: /mnt/data/pv-01
```

Then a matching PVC:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-claim
spec:
  storageClassName: manual
  accessModes: [ReadWriteOnce]
  resources:
    requests: {storage: 5Gi}
```

Binding works when SC name, access modes, and capacity match.

---

## VolumeBindingMode

A StorageClass attribute controlling **when** a PV is created/bound:

| Mode | When binding happens | Use case |
|------|----------------------|----------|
| `Immediate` | As soon as PVC is created. | Most clouds default. |
| `WaitForFirstConsumer` | Only once a pod referencing the PVC is scheduled. | Topology-aware (local volumes, multi-AZ). |

Check:

```bash
oc get sc <name> -o yaml | grep volumeBindingMode
```

Symptom of misconfiguration: PVC stuck `Pending` forever with no events — usually `WaitForFirstConsumer` set and no pod has been scheduled yet, or zone mismatch.

---

## Resizing a PVC (online expansion)

If the SC has `allowVolumeExpansion: true`:

```bash
oc patch pvc db-data -p \
  '{"spec":{"resources":{"requests":{"storage":"5Gi"}}}}'
```

Watch the PVC's status: it will go to `Resizing` → `FileSystemResizePending` and finally back to `Bound` at the new size. The pod usually needs to be restarted for the filesystem to expand.

You cannot shrink. You cannot resize if the SC has `allowVolumeExpansion: false` (or absent).

---

## VolumeSnapshot (cloud / CSI backends)

If the storage backend supports it:

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: db-snap-1
  namespace: myapp
spec:
  volumeSnapshotClassName: csi-snapclass
  source:
    persistentVolumeClaimName: db-data
```

Restore by creating a new PVC with `dataSource` pointing at the snapshot:

```yaml
spec:
  dataSource:
    name: db-snap-1
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes: [ReadWriteOnce]
  resources:
    requests: {storage: 2Gi}
```

Probably out of scope for EX280, but useful to know exists.

---

## Non-persistent volume types (still appear in tasks)

### `emptyDir` — scratch space, dies with the pod

```yaml
volumes:
- name: scratch
  emptyDir:
    sizeLimit: 500Mi
```

Use case: scratch files, in-memory caches (`emptyDir: {medium: Memory}`), tmp scratch between init container and main.

### `configMap` and `secret` as volumes

Already covered in `02-resource-manifests.md`, but the volume mount syntax is identical to a PVC mount — only the `volumes:` entry differs:

```yaml
volumes:
- name: app-config
  configMap:
    name: my-config
- name: app-secret
  secret:
    secretName: my-secret
    defaultMode: 0400
```

### `hostPath` — pod gets a directory on the node

```yaml
volumes:
- name: host-data
  hostPath:
    path: /var/log/app
    type: DirectoryOrCreate
```

Requires `hostmount-anyuid` or `privileged` SCC. Almost never used in production. Don't reach for it unless a task explicitly demands it.

---

## StatefulSet with volumeClaimTemplates (advanced but possible)

StatefulSets get a PVC **per pod**, automatically named `<claimTemplate>-<sts-name>-<ordinal>`:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: pg
spec:
  serviceName: pg
  replicas: 3
  selector: {matchLabels: {app: pg}}
  template:
    metadata: {labels: {app: pg}}
    spec:
      containers:
      - name: pg
        image: quay.io/sclorg/postgresql-15-c9s:latest
        volumeMounts:
        - {name: data, mountPath: /var/lib/pgsql/data}
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ReadWriteOnce]
      resources:
        requests: {storage: 1Gi}
```

This creates `data-pg-0`, `data-pg-1`, `data-pg-2` PVCs automatically.

---

## Templates that handle storage for you

Several built-in templates in `openshift` namespace include a PVC:

```bash
oc get templates -n openshift | grep -i persistent
# postgresql-persistent
# mysql-persistent
# mariadb-persistent
# redis-persistent
# mongodb-persistent

oc process openshift//postgresql-persistent \
  -p POSTGRESQL_USER=app \
  -p POSTGRESQL_PASSWORD=secret \
  -p POSTGRESQL_DATABASE=appdb \
  -p VOLUME_CAPACITY=2Gi \
  | oc apply -f -
```

These pull from the default StorageClass automatically.

---

## Troubleshooting storage

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `PVC` stuck `Pending` | No SC matches / no default SC / no PV with matching capacity & mode | `oc describe pvc <name>` → check events; verify SC exists and is default |
| `Pod` stuck `ContainerCreating`, event "MountVolume.SetUp failed" | Permissions on the volume don't match container UID (SCC issue) | Check SCC; consider `fsGroup` in pod spec, or anyuid SCC |
| `Pod` stuck `Pending` "0/N nodes had taints / volume node affinity conflict" | Zone-locked PV, pod scheduled in different zone | Recreate PVC; with `WaitForFirstConsumer`, schedule pod with desired zone selector |
| Data loss after pod delete | Reclaim policy was `Delete` on a dynamic PV | Set new SC's policy to `Retain` for important data |
| Can't resize PVC | `allowVolumeExpansion: false` on SC | Use a different SC or recreate with new size |

```bash
# Top-down debug
oc describe pvc <name>            # events at the bottom
oc describe pv <name>             # provisioner reasons
oc describe pod <pod> | grep -A5 Events
oc get events --sort-by=.lastTimestamp | tail
```

---

## Labs

### Lab S.1 — Dynamic PVC for postgres

The core storage skill: a PVC that a StorageClass fills automatically, mounted into a database, with data surviving a pod delete.

**Prerequisites:**
- A default StorageClass (`oc get sc` shows one marked `(default)`). Developer Sandbox, CRC, and most clusters have one.
- Project: `oc new-project db-lab`.

---

#### Step 1 — Create project `db-lab`

<details>
<summary>💡 Solution</summary>

```bash
oc new-project db-lab

# Confirm a default StorageClass exists — dynamic provisioning depends on it
oc get sc
# NAME            PROVISIONER            RECLAIMPOLICY   VOLUMEBINDINGMODE      DEFAULT
# gp3-csi (default) ebs.csi.aws.com      Delete          WaitForFirstConsumer   true
```

If no SC is marked default, either specify `storageClassName` explicitly in the PVC (Step 2) or set a default (see Lab S.4).

</details>

---

#### Step 2 — Apply the Deployment + PVC

<details>
<summary>💡 Solution</summary>

```bash
cat <<'EOF' | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: db-data
  namespace: db-lab
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 2Gi
  # storageClassName omitted → uses the cluster default SC
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: db
  namespace: db-lab
spec:
  replicas: 1
  selector: {matchLabels: {app: db}}
  template:
    metadata: {labels: {app: db}}
    spec:
      containers:
      - name: db
        image: quay.io/sclorg/postgresql-15-c9s:latest
        env:
        - {name: POSTGRESQL_USER, value: app}
        - {name: POSTGRESQL_PASSWORD, value: secret}
        - {name: POSTGRESQL_DATABASE, value: appdb}
        ports:
        - {containerPort: 5432}
        volumeMounts:
        - name: data
          mountPath: /var/lib/pgsql/data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: db-data
EOF

oc rollout status deployment/db -n db-lab
```

**Confirm the PVC bound** (a PV was dynamically provisioned to satisfy it):

```bash
oc get pvc db-data -n db-lab
# NAME      STATUS   VOLUME        CAPACITY   ACCESS MODES   STORAGECLASS
# db-data   Bound    pvc-abc123    2Gi        RWO            gp3-csi
```

`STATUS: Bound` = success. If it's `Pending`, run `oc describe pvc db-data` and read the events (usually "no default SC" or, with `WaitForFirstConsumer`, "waiting for first consumer to be scheduled" — which resolves once the pod schedules).

</details>

---

#### Step 3 — Insert a row

<details>
<summary>💡 Solution</summary>

```bash
oc exec -n db-lab deploy/db -- psql -U app -d appdb -c \
  "CREATE TABLE t (id int); INSERT INTO t VALUES (42);"
# CREATE TABLE
# INSERT 0 1

# Read it back
oc exec -n db-lab deploy/db -- psql -U app -d appdb -c "SELECT * FROM t;"
#  id
# ----
#  42
```

</details>

---

#### Step 4 — Delete the pod and confirm the new pod sees the row

<details>
<summary>💡 Solution</summary>

```bash
# Delete the running pod — the Deployment immediately creates a replacement
oc delete pod -l app=db -n db-lab
# pod "db-xxxxx" deleted

oc rollout status deployment/db -n db-lab
# waits for the new pod to be Ready

# The new pod mounts the SAME PVC → the data is still there
oc exec -n db-lab deploy/db -- psql -U app -d appdb -c "SELECT * FROM t;"
#  id
# ----
#  42
```

**Why the data survived:** the pod is ephemeral, but the PVC (and its backing PV) is not. When the Deployment recreated the pod, it re-attached the same `db-data` PVC at the same mount path, so PostgreSQL found its existing data files. This is the entire point of persistent storage — contrast with `emptyDir`, which would have been wiped.

**Verification checklist:**

```bash
oc get pvc db-data -n db-lab -o jsonpath='{.status.phase}{"\n"}'    # Bound
oc exec -n db-lab deploy/db -- psql -U app -d appdb -c "SELECT count(*) FROM t;"  # 1
```

Keep this project for Lab S.3 (resize). Otherwise: `oc delete project db-lab`.

</details>

---

### Lab S.2 — Static PV with manual SC

Static provisioning: an admin pre-creates a PV, and a PVC binds to it by matching class, size, and access mode. Useful when there's no dynamic provisioner, or you're pinning to specific local storage.

**Prerequisites:**
- Cluster-admin (PVs are cluster-scoped).
- Project: `oc new-project static-lab`.
- A single-node cluster (CRC/SNO) makes hostPath predictable; on multi-node the pod must land on the node holding the path.

---

#### Step 1 — Create a 1Gi hostPath PV with SC `manual`

<details>
<summary>💡 Solution</summary>

```bash
cat <<'EOF' | oc apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: local-pv
spec:
  capacity:
    storage: 1Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath:
    path: /tmp/pv1
    type: DirectoryOrCreate
EOF

oc get pv local-pv
# NAME       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      STORAGECLASS
# local-pv   1Gi        RWO            Retain           Available   manual
```

`STATUS: Available` = the PV exists and is waiting for a claim.

**Why `storageClassName: manual`:** this is a made-up class name with **no provisioner** behind it. Using a named-but-nonexistent class prevents the default dynamic provisioner from interfering — the PVC will only bind to a PV that also says `manual`. Using `""` (empty string) also disables dynamic provisioning but is easier to get wrong.

**hostPath caution:** `hostPath` mounts a directory from the node's own filesystem. It's fine for single-node labs but never for production (data is tied to one node, no isolation). The exam might use it for a static-PV demonstration; real workloads use CSI-backed dynamic storage.

</details>

---

#### Step 2 — Create a PVC requesting 1Gi, SC `manual`

<details>
<summary>💡 Solution</summary>

```bash
cat <<'EOF' | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: lab-pvc
  namespace: static-lab
spec:
  storageClassName: manual
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF

oc get pvc lab-pvc -n static-lab
# NAME      STATUS   VOLUME     CAPACITY   ACCESS MODES   STORAGECLASS
# lab-pvc   Bound    local-pv   1Gi        RWO            manual
```

**Binding conditions — all must match** for a PVC to bind to a static PV:
1. `storageClassName` matches (`manual` = `manual`).
2. Access modes are compatible (PVC's RWO ⊆ PV's RWO).
3. PV capacity ≥ PVC request (PV 1Gi ≥ PVC 1Gi).
4. No other PVC has already claimed the PV.

If any fails, the PVC stays `Pending`. `oc describe pvc lab-pvc` shows why.

</details>

---

#### Step 3 — Mount into a pod, write a file, delete the pod, verify persistence

<details>
<summary>💡 Solution</summary>

```bash
cat <<'EOF' | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: writer
  namespace: static-lab
spec:
  replicas: 1
  selector: {matchLabels: {app: writer}}
  template:
    metadata: {labels: {app: writer}}
    spec:
      containers:
      - name: c
        image: registry.access.redhat.com/ubi9/ubi-minimal:latest
        command: ["sleep","infinity"]
        volumeMounts:
        - name: vol
          mountPath: /data
      volumes:
      - name: vol
        persistentVolumeClaim:
          claimName: lab-pvc
EOF

oc rollout status deployment/writer -n static-lab

# Write a file to the mounted volume
oc exec -n static-lab deploy/writer -- sh -c 'echo "persisted!" > /data/proof.txt'
oc exec -n static-lab deploy/writer -- cat /data/proof.txt
# persisted!

# Delete the pod; the Deployment recreates it, remounting the same PVC
oc delete pod -l app=writer -n static-lab
oc rollout status deployment/writer -n static-lab

# File survived
oc exec -n static-lab deploy/writer -- cat /data/proof.txt
# persisted!
```

**Gotcha — hostPath on multi-node:** if the replacement pod schedules onto a *different* node than the one holding `/tmp/pv1`, the file won't be there (each node has its own `/tmp`). On CRC/SNO there's only one node, so it always works. This is exactly why hostPath is lab-only.

</details>

---

#### Step 4 — Delete the PVC; observe what happens to the PV

<details>
<summary>💡 Solution</summary>

```bash
# Delete the deployment first (releases the mount), then the PVC
oc delete deployment writer -n static-lab
oc delete pvc lab-pvc -n static-lab

# Check the PV's status now
oc get pv local-pv
# NAME       CAPACITY   RECLAIM POLICY   STATUS     CLAIM               STORAGECLASS
# local-pv   1Gi        Retain           Released   static-lab/lab-pvc  manual
```

**`STATUS: Released`, not `Available`.** Because the reclaim policy is `Retain`, when the PVC is deleted:
- The PV is **not** deleted (data at `/tmp/pv1` is preserved).
- The PV moves to `Released` — it still references the old claim and **cannot be re-bound** by a new PVC until an admin clears it.

**To make the PV reusable**, remove the stale claim reference:

```bash
oc patch pv local-pv --type=json -p='[{"op":"remove","path":"/spec/claimRef"}]'
oc get pv local-pv
# STATUS now Available again
```

**Reclaim policy recap:**

| Policy | On PVC delete |
|--------|---------------|
| `Retain` | PV kept, moves to `Released`, admin must manually clean/clear claimRef to reuse |
| `Delete` | PV **and** backing storage destroyed (default for dynamic provisioning) |
| `Recycle` | Deprecated — don't use |

**Cleanup:**

```bash
oc delete pv local-pv
oc delete project static-lab
```

</details>

---

### Lab S.3 — Resize an existing PVC

Online expansion grows a PVC without recreating it — if the StorageClass allows it. You can grow, never shrink.

**Prerequisites:**
- The `db-lab` project and `db-data` PVC from Lab S.1 (or recreate them).
- A StorageClass with `allowVolumeExpansion: true` (most CSI drivers support it).

---

#### Step 1 — Confirm the StorageClass allows expansion

<details>
<summary>💡 Solution</summary>

```bash
# Find the SC the PVC uses
SC=$(oc get pvc db-data -n db-lab -o jsonpath='{.spec.storageClassName}')
echo "StorageClass: $SC"

# Does it allow expansion?
oc get sc $SC -o jsonpath='{.allowVolumeExpansion}{"\n"}'
# true
```

**If it prints `false` or nothing:** the SC doesn't support online resize; you'd have to create a new larger PVC and copy data across. Most modern CSI drivers (EBS, Azure Disk, GCE PD, CephFS/RBD) support expansion. The old in-tree `hostPath`/`manual` PVs from Lab S.2 do **not**.

</details>

---

#### Step 2 — Patch the PVC from 2Gi → 5Gi

<details>
<summary>💡 Solution</summary>

```bash
oc patch pvc db-data -n db-lab --type=merge \
  -p '{"spec":{"resources":{"requests":{"storage":"5Gi"}}}}'
# persistentvolumeclaim/db-data patched
```

**Alternative — `oc edit`:**

```bash
oc edit pvc db-data -n db-lab
# change spec.resources.requests.storage: 2Gi → 5Gi, save
```

**Watch the resize progress** (it passes through intermediate conditions):

```bash
oc get pvc db-data -n db-lab
# NAME      STATUS   VOLUME       CAPACITY   ACCESS MODES   STORAGECLASS
# db-data   Bound    pvc-abc123   2Gi        RWO            gp3-csi
# (CAPACITY still shows 2Gi until the filesystem resize completes)

oc describe pvc db-data -n db-lab | grep -A5 Conditions
# Conditions:
#   Type                      Status
#   FileSystemResizePending   True     ← waiting for the pod to pick up the new size
```

**Gotcha — you cannot shrink.** Patching to a smaller size than current is rejected:

```
The PersistentVolumeClaim "db-data" is invalid: spec.resources.requests.storage:
Forbidden: field can not be less than previous value
```

</details>

---

#### Step 3 — Restart the pod; verify the filesystem reports the new size

<details>
<summary>💡 Solution</summary>

Many CSI drivers need the pod to restart for the *filesystem* (as opposed to the block device) to expand:

```bash
oc rollout restart deployment/db -n db-lab
oc rollout status deployment/db -n db-lab

# Now the PVC shows the new capacity
oc get pvc db-data -n db-lab
# db-data   Bound   pvc-abc123   5Gi   RWO   gp3-csi     ← 5Gi

# And the mounted filesystem inside the pod reflects it
oc exec -n db-lab deploy/db -- df -h /var/lib/pgsql/data
# Filesystem      Size  Used Avail Use% Mounted on
# /dev/xvdbf      5.0G  ...  ...   ...  /var/lib/pgsql/data
```

**The two-stage expansion:**
1. **Volume expansion** — the CSI driver grows the underlying block device (happens after the patch).
2. **Filesystem expansion** — the filesystem on that device is grown to fill it (happens on pod restart, or online for some drivers).

The `FileSystemResizePending` condition clearing + `df -h` showing 5.0G confirms both stages completed.

**Cleanup:**

```bash
oc delete project db-lab
```

</details>

---

### Lab S.4 — Default StorageClass swap

Exactly one StorageClass should carry the "default" annotation; PVCs that omit `storageClassName` use it. This lab swaps the default and proves it, then restores.

**Prerequisites:**
- Cluster-admin.
- At least one existing StorageClass.

---

#### Step 1 — List SCs and find the current default

<details>
<summary>💡 Solution</summary>

```bash
oc get sc
# NAME              PROVISIONER        ...   DEFAULT
# gp3-csi (default) ebs.csi.aws.com    ...   true

# Precisely identify the default via its annotation:
oc get sc -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}'
# gp3-csi
```

The default is marked by the annotation `storageclass.kubernetes.io/is-default-class: "true"`. Record the current default's name — you'll restore it in Step 5.

```bash
OLD_DEFAULT=gp3-csi     # set to whatever your cluster shows
```

</details>

---

#### Step 2 — Create a "fake" SC `lab-default` by copying the existing one

<details>
<summary>💡 Solution</summary>

```bash
# Export the current default, strip immutable/status fields, rename to lab-default
oc get sc $OLD_DEFAULT -o yaml \
  | sed '/uid:/d; /resourceVersion:/d; /creationTimestamp:/d; /is-default-class/d' \
  | sed "s/name: $OLD_DEFAULT/name: lab-default/" \
  > lab-default-sc.yaml

# Remove the .metadata.annotations default marker if the sed didn't catch it, then apply
oc apply -f lab-default-sc.yaml

oc get sc
# NAME              PROVISIONER        ...   DEFAULT
# gp3-csi (default) ebs.csi.aws.com    ...   true
# lab-default       ebs.csi.aws.com    ...
```

**Simplest reliable approach** — write it fresh instead of sed-ing (adjust provisioner to match your cluster's):

```bash
cat <<EOF | oc apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: lab-default
provisioner: $(oc get sc $OLD_DEFAULT -o jsonpath='{.provisioner}')
parameters: $(oc get sc $OLD_DEFAULT -o jsonpath='{.parameters}' | sed 's/map\[//;s/\]//')
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOF
```

(If the `parameters` interpolation is fiddly, just create an SC with empty `parameters: {}` — for this lab it only needs to exist and be selectable.)

</details>

---

#### Step 3 — Make `lab-default` the default; unset the old one

<details>
<summary>💡 Solution</summary>

**Two patches — there must never be two defaults at once:**

```bash
# 1. Unset the old default
oc patch sc $OLD_DEFAULT -p \
  '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'

# 2. Set the new default
oc patch sc lab-default -p \
  '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Verify exactly one default
oc get sc
# NAME                  PROVISIONER       ...   DEFAULT
# gp3-csi               ebs.csi.aws.com   ...
# lab-default (default) ebs.csi.aws.com   ...   true
```

**Gotcha — two defaults is an error state.** If both are marked `true`, PVC creation without an explicit class becomes ambiguous and Kubernetes picks unpredictably (and warns). Always unset the old one when setting a new one.

</details>

---

#### Step 4 — Create a PVC with no `storageClassName`; confirm it binds via the new default

<details>
<summary>💡 Solution</summary>

```bash
oc new-project sc-test

cat <<'EOF' | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: default-test
  namespace: sc-test
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests: {storage: 1Gi}
  # storageClassName intentionally omitted → picks up the current default
EOF

oc get pvc default-test -n sc-test
# NAME           STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS
# default-test   Pending   ...                                lab-default   ← got the NEW default
```

The `STORAGECLASS` column shows `lab-default`, proving the omitted-class PVC picked up the newly-designated default. (With `WaitForFirstConsumer` it stays `Pending` until a pod uses it — that's expected, not a failure.)

**Prove it binds with a consumer:**

```bash
oc run consumer --image=registry.access.redhat.com/ubi9/ubi-minimal:latest \
  -n sc-test --restart=Never --overrides='
{"spec":{"containers":[{"name":"c","image":"registry.access.redhat.com/ubi9/ubi-minimal:latest","command":["sleep","300"],"volumeMounts":[{"name":"v","mountPath":"/data"}]}],"volumes":[{"name":"v","persistentVolumeClaim":{"claimName":"default-test"}}]}}'
oc get pvc default-test -n sc-test -w
# ... STATUS becomes Bound once the consumer schedules
```

</details>

---

#### Step 5 — Restore the original default

<details>
<summary>💡 Solution</summary>

```bash
# Set the original back as default
oc patch sc $OLD_DEFAULT -p \
  '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Unset lab-default
oc patch sc lab-default -p \
  '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'

# Verify original default is restored, exactly one default
oc get sc

# Clean up the lab artifacts
oc delete sc lab-default
oc delete project sc-test
```

**Why this matters on the exam:** a task might say "make `fast-ssd` the default StorageClass." The answer is the two-patch dance: annotate the new one `true`, annotate the old one `false`. Forgetting to unset the old one is the classic mistake.

</details>

---

### Lab S.5 — RWX shared volume (only if your lab has RWX backend)

ReadWriteMany lets multiple pods mount the same volume read-write simultaneously — impossible with block storage (RWO), requires a file backend (NFS, CephFS, EFS, Azure Files).

**Prerequisites:**
- A StorageClass backed by RWX-capable storage (CephFS via ODF, NFS, EFS, Azure Files). Check with the note in Step 1.
- **Developer Sandbox and plain CRC typically lack RWX** — skip this lab if so.
- Project: `oc new-project rwx-lab`.

---

#### Step 1 — Confirm an RWX-capable StorageClass exists

<details>
<summary>💡 Solution</summary>

```bash
oc get sc
# Look for a file-based provisioner, e.g.:
#   ocs-storagecluster-cephfs   openshift-storage.cephfs.csi.ceph.com
#   efs-sc                      efs.csi.aws.com
#   nfs-csi                     nfs.csi.k8s.io
#   azurefile-csi               file.csi.azure.com
```

Block-based classes (`ebs.csi.aws.com`, `disk.csi.azure.com`, `pd.csi.storage.gke.io`) are **RWO only** and can't do this lab. You need a file/shared provisioner.

**If you have none:** skip S.5. RWX isn't a standalone EX280 objective; RWO covers the vast majority of exam scenarios. Note the concept and move on.

</details>

---

#### Step 2 — Provision an RWX PVC

<details>
<summary>💡 Solution</summary>

```bash
RWX_SC=ocs-storagecluster-cephfs      # set to your RWX-capable class

cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: shared-data
  namespace: rwx-lab
spec:
  storageClassName: $RWX_SC
  accessModes:
  - ReadWriteMany          # ← the key field
  resources:
    requests:
      storage: 1Gi
EOF

oc get pvc shared-data -n rwx-lab
# NAME          STATUS   VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS
# shared-data   Bound    pvc-...  1Gi        RWX            ocs-storagecluster-cephfs
```

`ACCESS MODES: RWX` confirms the shared mount. If binding fails with an access-mode error, the SC doesn't support RWX.

</details>

---

#### Step 3 — Run two Deployments mounting it; write from A, read from B

<details>
<summary>💡 Solution</summary>

```bash
# Deployment A
cat <<'EOF' | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: {name: writer-a, namespace: rwx-lab}
spec:
  replicas: 1
  selector: {matchLabels: {app: writer-a}}
  template:
    metadata: {labels: {app: writer-a}}
    spec:
      containers:
      - name: c
        image: registry.access.redhat.com/ubi9/ubi-minimal:latest
        command: ["sleep","infinity"]
        volumeMounts: [{name: shared, mountPath: /shared}]
      volumes:
      - name: shared
        persistentVolumeClaim: {claimName: shared-data}
EOF

# Deployment B — SAME PVC
cat <<'EOF' | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: {name: reader-b, namespace: rwx-lab}
spec:
  replicas: 1
  selector: {matchLabels: {app: reader-b}}
  template:
    metadata: {labels: {app: reader-b}}
    spec:
      containers:
      - name: c
        image: registry.access.redhat.com/ubi9/ubi-minimal:latest
        command: ["sleep","infinity"]
        volumeMounts: [{name: shared, mountPath: /shared}]
      volumes:
      - name: shared
        persistentVolumeClaim: {claimName: shared-data}
EOF

oc rollout status deployment/writer-a -n rwx-lab
oc rollout status deployment/reader-b -n rwx-lab

# Write from A
oc exec -n rwx-lab deploy/writer-a -- sh -c 'echo "written by A at $(date)" > /shared/msg.txt'

# Read from B — sees A's file because they share the same volume
oc exec -n rwx-lab deploy/reader-b -- cat /shared/msg.txt
# written by A at ...
```

**Why this works with RWX but would fail with RWO:** with an RWO PVC, the second pod's mount would block (the volume can only be attached to one node r/w at a time), and if both pods landed on different nodes, one would be stuck `ContainerCreating` with a "Multi-Attach error". RWX file storage has no such restriction — many pods across many nodes mount it simultaneously.

**Common RWX use cases:** shared upload directories, CMS media folders, build caches, anything where multiple replicas need a common read-write filesystem.

**Cleanup:**

```bash
oc delete project rwx-lab
```

</details>

---

---

## Timed drill (10 min)

1. (2 min) Show the default SC name.
2. (2 min) Create a PVC `quick-pvc` of 1Gi RWO from default SC.
3. (3 min) Create a busybox Deployment mounting it at `/data`, write `hello` to `/data/file`.
4. (1 min) Delete the pod; wait for the new one.
5. (2 min) Verify `/data/file` still contains `hello`.

If you can do this in 10 minutes from memory, storage is no longer a risk on the exam.

---

## What to skip (low priority)

- CSI driver internals.
- Writing your own StorageClass for a new backend (operator-installed in real life).
- VolumeSnapshot details beyond knowing they exist.
- ODF / Ceph configuration (separate exam: EX358).

What to **definitely** know cold:
- PVC YAML with access mode, size, optional storageClassName.
- Mounting a PVC into a Deployment.
- Default SC inspection.
- Reclaim policy difference (Delete vs Retain).
- Reading PVC events to diagnose `Pending`.
