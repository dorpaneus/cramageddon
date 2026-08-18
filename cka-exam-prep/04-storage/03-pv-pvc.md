# PersistentVolumes & PersistentVolumeClaims

> **Objective (CNCF):** Understand persistent volumes and use them in pods/Deployments/StatefulSets.
> **Domain:** Storage (10%) — **Exam frequency:** ⭐⭐⭐⭐ (almost every exam has a PV/PVC task)

---

## The two-piece model

```
   PVC = "I want 5Gi of RWO storage"     (user / app team)
   PV  = "Here is 10Gi RWO storage at /mnt/disk-A"   (admin / dynamic provisioner)

   Controller binds them 1:1 if compatible.
   Pod references the PVC (not the PV) by name.
```

You almost never write a PV in production — dynamic provisioning makes one. On the exam, you might do both.

---

## PersistentVolume (PV)

```yaml
apiVersion: v1
kind: PersistentVolume
metadata: { name: data-pv-1 }
spec:
  capacity:
    storage: 10Gi
  volumeMode: Filesystem
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: standard               # PVCs must match this to bind
  hostPath:                                # which backend (one of many)
    path: /mnt/data
    type: DirectoryOrCreate
```

Cluster-scoped. **No namespace.**

---

## PersistentVolumeClaim (PVC)

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-pvc
  namespace: prod
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 5Gi
  storageClassName: standard               # leave unset to use default
  selector:                                # optional: pin to specific PV by labels
    matchLabels:
      tier: premium
```

Namespaced. The pod references it by name within the same namespace.

---

## Binding rules

A PVC binds to a PV that satisfies **all** of:

| Field | Match rule |
|---|---|
| `storageClassName` | Same value (or both empty for static no-class binding) |
| `accessModes` | PV's accessModes superset of PVC's |
| `capacity.storage` | PV ≥ PVC |
| `volumeMode` | Same (`Filesystem`/`Block`) |
| `selector` (PVC) | PV labels match if specified |

Binding is **1:1 and exclusive** — once bound, the PV is owned by that PVC for life.

---

## Using a PVC in a pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app
spec:
  containers:
  - name: app
    image: nginx
    volumeMounts:
    - name: data
      mountPath: /usr/share/nginx/html
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: data-pvc
```

For Deployments / StatefulSets, put the same `volumes` + `volumeMounts` in `spec.template.spec`.

---

## StatefulSet & volumeClaimTemplates

StatefulSets create a PVC **per pod** using a template:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata: { name: db }
spec:
  serviceName: db
  replicas: 3
  selector:
    matchLabels: { app: db }
  template:
    metadata: { labels: { app: db } }
    spec:
      containers:
      - name: db
        image: postgres:15
        volumeMounts:
        - { name: data, mountPath: /var/lib/postgresql/data }
  volumeClaimTemplates:
  - metadata: { name: data }
    spec:
      accessModes: [ReadWriteOnce]
      storageClassName: fast
      resources:
        requests:
          storage: 10Gi
```

Each pod (`db-0`, `db-1`, `db-2`) gets its own PVC: `data-db-0`, `data-db-1`, `data-db-2`. PVCs survive pod deletion — that's the point.

When you `kubectl delete statefulset db`, the PVCs **stay** by default. Delete them manually if you mean it.

---

## Phases

```
PV:   Available → Bound → Released → (manual: Available again | deleted)
PVC:  Pending → Bound → (deleted)
```

```bash
kubectl get pv,pvc
# pv:   STATUS column
# pvc:  STATUS column
```

`Pending` PVC means no PV matches. Common reasons:
- No default StorageClass.
- StorageClassName doesn't match any class/PV.
- No PV with sufficient capacity / matching access mode.
- Provisioner failing (dynamic) — check provisioner logs.

---

## Deletion semantics

```bash
kubectl delete pvc data-pvc
# 1. If pod still uses it → blocked until pod is gone (finalizer)
# 2. Then:
#    reclaimPolicy: Delete  → PV + storage destroyed
#    reclaimPolicy: Retain  → PV becomes Released (data kept)
```

A `kubectl delete pvc` that hangs is usually a pod still using it. Check:
```bash
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\t"}{.spec.volumes[?(@.persistentVolumeClaim)].persistentVolumeClaim.claimName}{"\n"}{end}' | grep data-pvc
```

---

## Exercises

### 1. PV + PVC + Pod end-to-end (static)

> Create:
> - PV `pv-data` (5Gi, hostPath `/mnt/data`, RWO, storageClassName `manual`).
> - PVC `pvc-data` requesting 3Gi RWO with same class.
> - Pod `app` mounting it at `/data`.

<details><summary>Solution</summary>

```yaml
apiVersion: v1
kind: PersistentVolume
metadata: { name: pv-data }
spec:
  capacity: { storage: 5Gi }
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath: { path: /mnt/data, type: DirectoryOrCreate }
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: pvc-data }
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: manual
  resources: { requests: { storage: 3Gi } }
---
apiVersion: v1
kind: Pod
metadata: { name: app }
spec:
  containers:
  - name: app
    image: nginx
    volumeMounts:
    - { name: data, mountPath: /data }
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: pvc-data
```

```bash
kubectl apply -f all.yaml
kubectl get pv,pvc,pod
# Expect pv Bound, pvc Bound, pod Running
```
</details>

### 2. PVC stuck Pending — diagnose

> PVC `data-pvc` is `Pending`. Find why.

<details><summary>Solution</summary>

```bash
kubectl describe pvc data-pvc
# Events at bottom often say:
#  - "waiting for a volume to be created" → dynamic, but provisioner failing
#  - "no persistent volumes available for this claim and no storage class" → no SC
#  - "storageClassName 'foo' not found"

# Check the requested class:
kubectl get sc

# Check provisioner pods (dynamic):
kubectl -n kube-system get pods | grep -i csi
kubectl -n kube-system logs <csi-controller-pod>

# For static: check if a matching PV exists
kubectl get pv
```
</details>

### 3. Mount a PVC in a Deployment

> Add a 5Gi RWO PVC (default storageclass) to Deployment `web`, mounted at `/var/www`.

<details><summary>Solution</summary>

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: web-data }
spec:
  accessModes: [ReadWriteOnce]
  resources: { requests: { storage: 5Gi } }
---
# Then edit the Deployment:
spec:
  template:
    spec:
      containers:
      - name: web
        # ...
        volumeMounts:
        - { name: data, mountPath: /var/www }
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: web-data
```

Note: RWO + multiple replicas works only if all pods land on the **same node** (rarely). For multi-replica web servers, RWX or a StatefulSet with per-pod PVCs is more appropriate.
</details>

### 4. Resize a PVC

> Grow `data-pvc` from 5Gi to 10Gi.

<details><summary>Solution</summary>

Prerequisite: `allowVolumeExpansion: true` on the StorageClass.

```bash
kubectl patch pvc data-pvc -p '{"spec":{"resources":{"requests":{"storage":"10Gi"}}}}'
kubectl get pvc data-pvc                # Capacity may take a moment to update
```

For some older drivers, the pod must be restarted to remount and grow the filesystem.
</details>

### 5. Delete a StatefulSet without losing data

> Delete StatefulSet `db` but keep all PVCs intact.

<details><summary>Solution</summary>

```bash
kubectl delete statefulset db --cascade=orphan
# PVCs remain. Pods are deleted.
```

Or, simpler: just `kubectl delete statefulset db`. PVCs are not deleted by default. The `--cascade=orphan` flag also leaves the pods alive (rarely what you want).
</details>

---

## Common pitfalls

| Pitfall | Effect |
|---|---|
| Created PVC; pod still pending | PVC pending — check storageClassName + provisioner |
| Pod uses PVC across namespaces | Not supported; PVC must be in pod's namespace |
| Multiple replicas with RWO | Pods scheduled on different nodes → all but one in `ContainerCreating` |
| Selector on PVC matches nothing | Pending despite a "good enough" PV existing |
| Deleted StatefulSet, expected PVCs gone | They aren't (by design); delete explicitly |
| `kubectl delete pvc` hangs | Pod still using it — delete pod first |
| Resized PVC, filesystem didn't grow | Recreate pod to trigger online expansion (for some drivers) |

---

## Doc bookmarks

- https://kubernetes.io/docs/concepts/storage/persistent-volumes/
- https://kubernetes.io/docs/tasks/configure-pod-container/configure-persistent-volume-storage/
- https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/

---

## Speed drill

Goal: PV + PVC + Pod manifest in **≤ 3 minutes**.

```bash
# Skeleton from explain:
kubectl explain pv.spec | less
kubectl explain pvc.spec | less

# Read state in one line:
kubectl get pv,pvc -A -o wide
```
