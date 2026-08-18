# Volume Types, Access Modes & Reclaim Policies

> **Objective (CNCF):** Understand volume types, access modes, and reclaim policies.
> **Domain:** Storage (10%) — **Exam frequency:** ⭐⭐

---

## Volume types

Kubernetes supports many volume kinds. For the exam, know these:

### Ephemeral (pod-lifetime)

| Type | Lives | Use case |
|---|---|---|
| `emptyDir` | Pod lifetime | Scratch space, IPC between containers in a pod |
| `emptyDir` (with `medium: Memory`) | Pod lifetime, RAM-backed (tmpfs) | Fast temp data |
| `configMap` | Pod lifetime | Inject config files |
| `secret` | Pod lifetime | Inject secrets |
| `downwardAPI` | Pod lifetime | Inject pod metadata |
| `projected` | Pod lifetime | Combine multiple sources |

### Persistent

| Type | Persists beyond pod |
|---|---|
| `persistentVolumeClaim` | ✅ — via a PV |
| `hostPath` | ✅ — but tied to the node (rarely a good idea) |
| `csi` | ✅ — generic CSI driver volume |
| `nfs`, `iscsi`, `cephfs`, … | ✅ — direct (mostly legacy; CSI-based is preferred) |

---

## emptyDir (the most common ephemeral)

```yaml
apiVersion: v1
kind: Pod
metadata: { name: cache }
spec:
  containers:
  - name: app
    image: nginx
    volumeMounts:
    - name: scratch
      mountPath: /tmp/scratch
  volumes:
  - name: scratch
    emptyDir:
      sizeLimit: 500Mi               # optional cap
      # medium: Memory               # uncomment for tmpfs
```

Deleted with the pod. Shared between containers in the same pod.

---

## hostPath (use with care)

Mounts a path from the **host node** into the pod.

```yaml
volumes:
- name: data
  hostPath:
    path: /var/lib/myapp
    type: DirectoryOrCreate
```

`type` values: `Directory`, `DirectoryOrCreate`, `File`, `FileOrCreate`, `Socket`, ... Validates that the path matches that kind.

**Why care:**
- Ties pod to a specific node (rescheduled elsewhere → no data).
- Security risk: container can access node filesystem.
- Useful for: node-level agents (logging, monitoring), reading `/etc/...`, lab work.

---

## Access modes

Declared on PVs and PVCs; describes how the volume can be mounted:

| Mode | Short | Meaning |
|---|---|---|
| `ReadWriteOnce` | RWO | Mounted as read-write by a **single node** |
| `ReadOnlyMany` | ROX | Mounted read-only by many nodes |
| `ReadWriteMany` | RWX | Mounted read-write by many nodes |
| `ReadWriteOncePod` | RWOP | (k8s 1.22+) Read-write by **a single pod** (stronger than RWO) |

**Critical:** RWO does *not* mean "one pod" — it means one **node**. Multiple pods on the same node can share an RWO volume. Use **RWOP** to require single-pod access.

### Which backends support what?

| Backend | RWO | ROX | RWX |
|---|---|---|---|
| AWS EBS | ✅ | ❌ | ❌ |
| GCE PD | ✅ | ❌ | ❌ |
| Azure Disk | ✅ | ❌ | ❌ |
| NFS / EFS / Azure Files | ✅ | ✅ | ✅ |
| CephFS | ✅ | ✅ | ✅ |
| Local volume | ✅ | ❌ | ❌ |

Want RWX → use NFS, CephFS, or a managed file service. Block storage is generally RWO only.

---

## Reclaim policies (PV level)

What happens to the underlying storage when a PVC is deleted:

| Policy | Effect |
|---|---|
| `Delete` | PV + backing storage deleted. Default for dynamically provisioned PVs (depending on the StorageClass). |
| `Retain` | PV kept, status becomes `Released`. Admin must clean it up before the PV can be reused. |
| `Recycle` | **Deprecated** — basic `rm -rf /thevolume/*`. Don't use. |

Set it:
- On the StorageClass → `reclaimPolicy: Retain` for all new PVs from that class.
- On an existing PV → `kubectl patch pv <name> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'`.

### Released vs Available

After `Delete` of PVC with `Retain` policy:
- PV stays.
- Status becomes `Released` — bound to the (deleted) PVC's UID, won't auto-bind to a new claim.
- Admin must:
  1. Clean data on the underlying volume.
  2. Edit the PV and **clear `spec.claimRef`** (or delete + recreate the PV).
  3. PV status → `Available`.

```bash
kubectl patch pv <name> --type=json -p='[{"op":"remove","path":"/spec/claimRef"}]'
```

---

## Volume modes (filesystem vs block)

```yaml
spec:
  volumeMode: Filesystem      # default; mounted under mountPath
  # OR:
  volumeMode: Block           # raw block device exposed as /dev/...
```

`Block` mode skips filesystem; pod sees a raw device. Used for databases that manage their own block layout. Pod consumes via `volumeDevices` instead of `volumeMounts`:

```yaml
volumeDevices:
- name: data
  devicePath: /dev/xvda
```

Rare on the exam, but recognize the term.

---

## Subpath mounts

Mount only part of a volume:

```yaml
volumeMounts:
- name: data
  mountPath: /etc/config/app.conf
  subPath: app.conf
```

Useful for putting a single file (from a ConfigMap or Secret) into a specific path without replacing the whole directory.

`subPathExpr`: same idea but supports env var substitution (`$(POD_NAME)/log`).

---

## Exercises

### 1. emptyDir between two containers

> Two containers in a pod: `writer` writes to `/data/log`, `reader` reads from `/data/log`. Share via emptyDir.

<details><summary>Solution</summary>

```yaml
apiVersion: v1
kind: Pod
metadata: { name: share }
spec:
  containers:
  - name: writer
    image: busybox
    command: ["sh","-c","while true; do date >> /data/log; sleep 5; done"]
    volumeMounts: [{ name: shared, mountPath: /data }]
  - name: reader
    image: busybox
    command: ["sh","-c","tail -f /data/log"]
    volumeMounts: [{ name: shared, mountPath: /data }]
  volumes:
  - name: shared
    emptyDir: {}
```
</details>

### 2. Change a PV's reclaim policy

> An existing PV `data-pv` has policy `Delete`. Change it to `Retain`.

<details><summary>Solution</summary>

```bash
kubectl patch pv data-pv -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
kubectl get pv data-pv     # RECLAIM POLICY column
```
</details>

### 3. Re-bind a Released PV

> PV `data-pv` is `Released`. The data is fine; you need a new PVC to bind to it.

<details><summary>Solution</summary>

```bash
# 1. Clear the claimRef
kubectl patch pv data-pv --type=json -p='[{"op":"remove","path":"/spec/claimRef"}]'

# 2. Confirm Available
kubectl get pv data-pv

# 3. Create a matching PVC (same size, access mode, storageClassName)
```
</details>

### 4. Mount one file from a ConfigMap

> ConfigMap `app-conf` has key `app.properties`. Mount only that file at `/etc/app/app.properties` without hiding `/etc/app/`.

<details><summary>Solution</summary>

```yaml
spec:
  containers:
  - name: app
    image: my/app
    volumeMounts:
    - name: cfg
      mountPath: /etc/app/app.properties
      subPath: app.properties
  volumes:
  - name: cfg
    configMap:
      name: app-conf
```

Without `subPath`, mounting at `/etc/app/app.properties` would shadow it as a directory.
</details>

---

## Common pitfalls

| Pitfall | Why it bites |
|---|---|
| Used `hostPath` and pod moved nodes | Data effectively gone |
| Asked for RWX on EBS | Stays Pending — EBS is RWO |
| Deleted PVC, lost data | Reclaim policy `Delete` |
| PV stuck `Released` | Clear `claimRef` before reuse |
| `emptyDir` for important data | Deleted with pod |
| Mounted ConfigMap without `subPath` | Hides existing directory contents |
| `volumeMode: Block` and used `volumeMounts` | Validation error — use `volumeDevices` |

---

## Doc bookmarks

- https://kubernetes.io/docs/concepts/storage/volumes/
- https://kubernetes.io/docs/concepts/storage/persistent-volumes/#access-modes
- https://kubernetes.io/docs/concepts/storage/persistent-volumes/#reclaiming
- https://kubernetes.io/docs/concepts/storage/persistent-volumes/#volume-mode

---

## Speed drill

```bash
# Quick eye on storage state
kubectl get pv -o wide
kubectl get pvc -A
kubectl describe pv <name>
kubectl describe pvc <name>
```
