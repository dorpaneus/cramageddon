# Domain 4: Storage (10%)

Smallest domain by weight, but easy points if you've done the labs.

## Objectives

| # | File | Topic |
|---|---|---|
| 1 | [01-storage-classes.md](01-storage-classes.md) | StorageClasses, provisioners, dynamic provisioning |
| 2 | [02-volume-modes-access.md](02-volume-modes-access.md) | Volume types, access modes, reclaim policies |
| 3 | [03-pv-pvc.md](03-pv-pvc.md) | Persistent Volumes & Persistent Volume Claims; mounting in pods |

## Mental model

```
   ┌───────────────────┐                     ┌────────────────┐
   │  StorageClass     │ ──provisioner──────▶│   provisioner  │
   │  (provisioner +   │                     │  (e.g. EBS CSI)│
   │   parameters)     │                     └───────┬────────┘
   └─────────┬─────────┘                             │ creates
             │ referenced by                         ▼
             ▼                            ┌────────────────────┐
   ┌───────────────────┐                  │   PersistentVolume │
   │       PVC         │◀─binds (1:1)────▶│       (PV)         │
   │  (claim:           │                  │  Capacity, access  │
   │   size + access)  │                  │  modes, reclaim    │
   └─────────┬─────────┘                  └─────────┬──────────┘
             │ referenced by                        │ backed by
             ▼                                      ▼
   ┌───────────────────┐                  ┌────────────────────┐
   │       Pod         │                  │   Backing storage  │
   │  volumes: pvc     │                  │  (EBS, NFS, ...)   │
   └───────────────────┘                  └────────────────────┘
```

## Exam emphasis

- Write a **PVC** matching a given size/access mode.
- Mount it in a Pod/Deployment.
- Understand **dynamic** vs **static** provisioning.
- Reclaim policies: `Delete` vs `Retain`.
- Access modes: `ReadWriteOnce` (RWO), `ReadOnlyMany` (ROX), `ReadWriteMany` (RWX), `ReadWriteOncePod` (RWOP).

Start with [01-storage-classes.md](01-storage-classes.md).
