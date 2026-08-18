# StorageClasses & Dynamic Provisioning

> **Objective (CNCF):** Understand storage classes, persistent volumes.
> **Domain:** Storage (10%) — **Exam frequency:** ⭐⭐⭐

---

## Why this matters

The StorageClass is what enables **dynamic** provisioning: a PVC requests storage, and Kubernetes creates the underlying PV automatically. Without StorageClasses, every PV must be hand-crafted.

---

## What a StorageClass is

A cluster-scoped resource describing **how** to provision storage:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
provisioner: ebs.csi.aws.com           # the CSI driver
parameters:                            # provisioner-specific
  type: gp3
  fsType: ext4
  encrypted: "true"
reclaimPolicy: Delete                  # Delete | Retain
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
mountOptions:
- noatime
```

Read it: *"Use the AWS EBS CSI driver to make gp3 volumes, ext4, encrypted. Delete the PV when the PVC is deleted. Wait until a pod schedules before binding (topology-aware). Allow `kubectl edit pvc` to grow it."*

---

## Key fields

### `provisioner`

Identifies the CSI driver. Examples:
- `ebs.csi.aws.com` (AWS EBS)
- `pd.csi.storage.gke.io` (GCE PD)
- `disk.csi.azure.com` (Azure Disk)
- `kubernetes.io/no-provisioner` (static — no dynamic creation)

### `reclaimPolicy`

What happens to a PV when the PVC is deleted:
- **`Delete`** — PV is deleted; backing storage is destroyed. Good for dev.
- **`Retain`** — PV is kept (status: Released); admin must manually clean up before reuse. Good for important data.

### `volumeBindingMode`

- **`Immediate`** (default) — PV created as soon as PVC is created. Risk: PV provisioned in zone-A, pod scheduled to zone-B → stuck.
- **`WaitForFirstConsumer`** — PV creation waits until a pod uses the PVC, so the provisioner can pick a topology-compatible zone. **Strongly preferred** for zonal storage.

### `allowVolumeExpansion`

If `true`, you can grow a PVC by editing its `.spec.resources.requests.storage`. Cannot shrink.

---

## Default StorageClass

A StorageClass can be marked the default with an annotation:

```yaml
metadata:
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
```

When a PVC omits `storageClassName`, the default is used. `kubectl get sc` shows `(default)` next to the default class.

```bash
kubectl get sc
# NAME              PROVISIONER         RECLAIMPOLICY   VOLUMEBINDINGMODE
# standard (default)  k8s.io/minikube-hostpath   Delete   Immediate

# Change default:
kubectl patch sc <name> -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl patch sc <old-default> -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
```

---

## Static vs dynamic provisioning

**Dynamic** (StorageClass driven):
```
PVC (with storageClassName) → provisioner creates PV → bound to PVC → pod mounts it
```

**Static** (admin creates PVs by hand):
```
admin creates PV  →  user creates PVC with matching size/accessModes  →  controller binds them
```

Setting `storageClassName: ""` on a PVC explicitly opts out of dynamic provisioning — bind only to a pre-existing PV with the same empty `storageClassName`.

---

## Inspecting a class

```bash
kubectl get sc
kubectl describe sc fast-ssd

# What's the provisioner doing? Logs of the CSI controller:
kubectl -n kube-system get pods | grep csi
kubectl -n kube-system logs <csi-controller-pod>
```

---

## Exercises

### 1. Create a StorageClass

> Create a StorageClass `fast` using provisioner `kubernetes.io/no-provisioner` with `Retain` reclaim policy and `WaitForFirstConsumer` binding.

<details><summary>Solution</summary>

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata: { name: fast }
provisioner: kubernetes.io/no-provisioner
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
```

```bash
kubectl apply -f sc.yaml
kubectl get sc
```
</details>

### 2. Change the default StorageClass

> `standard` is currently default. Make `fast` the default instead.

<details><summary>Solution</summary>

```bash
kubectl patch sc standard -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
kubectl patch sc fast -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

kubectl get sc          # only one (default) marker should appear
```
</details>

### 3. Expand a PVC

> A PVC `data-pvc` is 5Gi. Grow it to 10Gi.

<details><summary>Solution</summary>

Prerequisite: the StorageClass must have `allowVolumeExpansion: true`. Check:
```bash
kubectl get sc <name> -o jsonpath='{.allowVolumeExpansion}'
```

Then:
```bash
kubectl edit pvc data-pvc
# change spec.resources.requests.storage: 10Gi
```

Or:
```bash
kubectl patch pvc data-pvc -p '{"spec":{"resources":{"requests":{"storage":"10Gi"}}}}'
```

Filesystem expansion happens online for most CSI drivers when the pod is running (or after pod restart for older drivers).
</details>

### 4. Static provisioning end-to-end

> An admin pre-created a PV. Create a PVC that binds to it (no dynamic provisioning).

<details><summary>Solution</summary>

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: my-pvc }
spec:
  storageClassName: ""             # ← critical: opt out of default class
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 1Gi
```

The PV must also have `storageClassName: ""` (or no class) and equal or greater size + matching access modes.
</details>

---

## Common pitfalls

| Pitfall | Effect |
|---|---|
| PVC `Pending` forever | Often: no default SC, or class doesn't exist, or zone mismatch with `Immediate` binding |
| Deleted PVC and lost data | `reclaimPolicy: Delete` — use `Retain` for important data |
| Edited PVC size but storage didn't grow | `allowVolumeExpansion: false`, or CSI doesn't support online expansion |
| Multiple default StorageClasses | Behavior is undefined; pick one |
| Provisioner name typo | PVC stays Pending; no error in PVC itself — check StorageClass status / provisioner pod logs |
| Used `Immediate` binding for zonal storage | Pod scheduled in different zone than PV → "node has no access to PV" |

---

## Doc bookmarks

- https://kubernetes.io/docs/concepts/storage/storage-classes/
- https://kubernetes.io/docs/concepts/storage/persistent-volumes/
- https://kubernetes.io/docs/tasks/administer-cluster/change-default-storage-class/
- https://kubernetes.io/docs/concepts/storage/dynamic-provisioning/

---

## Speed drill

```bash
kubectl get sc
kubectl describe sc <name>
kubectl get pv,pvc -A
kubectl get csidrivers
```
