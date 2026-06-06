# ADR-007 — CSI Volume Snapshots pour la sauvegarde des PVCs PostgreSQL

| Champ      | Valeur                  |
|------------|-------------------------|
| Statut     | Accepté                 |
| Date       | 2026-06-05              |
| Auteur     | elGiordano              |
| Contexte   | Phase 04 — US Backup DR |

---

## Contexte

Velero propose deux mécanismes pour sauvegarder les PersistentVolumes :

1. **Native disk snapshots** via le plugin VSL (`VolumeSnapshotLocation`) — appelle directement l'API Azure Disk Snapshot
2. **CSI Volume Snapshots** via la feature `EnableCSI` — utilise le driver CSI du nœud (`disk.csi.azure.com`) et la CR `VolumeSnapshot`

Le plugin `velero-plugin-for-microsoft-azure` v1.11.0 (la version en production) prend en charge le Workload Identity (`useAAD: "true"`) **uniquement pour le BSL** (Blob Storage). Le VSL en v1.11.0 nécessite encore un fichier de credentials avec `AZURE_SUBSCRIPTION_ID` — incompatible avec notre configuration Workload Identity (zero-credentials).

Lors des tests, le backup avec `snapshotVolumes: true` et VSL configuré retournait :

```
PartiallyFailed: AZURE_SUBSCRIPTION_ID is required in credential file
```

---

## Décision

Utiliser les **CSI Volume Snapshots** (`disk.csi.azure.com`) comme mécanisme de sauvegarde des PVCs, à la place des native disk snapshots via VSL.

### Mécanisme technique

```
velero backup create
        │
        ├─ Manifests K8s → Azure Blob (via BSL + Workload Identity)
        │
        └─ PVCs (CSI snapshots)
               │
               ├─ Velero annote les PVC avec volumesnapshot-*
               ├─ Le driver disk.csi.azure.com crée un VolumeSnapshot K8s
               ├─ La VolumeSnapshotClass csi-azure-vsc route vers Azure Managed Disk Snapshot
               └─ Snapshot stocké dans le Resource Group du node pool (MC_...)
```

### Ressources K8s créées

**`k8s/velero/volumesnapshotclass.yaml`** (appliqué manuellement via `kubectl apply`) :

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: csi-azure-vsc
  labels:
    velero.io/csi-volumesnapshot-class: "true"
driver: disk.csi.azure.com
deletionPolicy: Retain
parameters:
  incremental: "true"
```

Le label `velero.io/csi-volumesnapshot-class: "true"` indique à Velero d'utiliser cette classe pour créer les snapshots CSI.

### Configuration Velero activée

```yaml
# k8s/velero/velero-values.yaml
configuration:
  features: EnableCSI    # Active la feature CSI dans Velero
```

### Où sont stockés les snapshots CSI

Les snapshots CSI (`disk.csi.azure.com`) sont des **Azure Managed Disk Snapshots** stockés dans le Resource Group du node pool AKS :

```
Resource Group: MC_rg-formation-ecom-aks_aks-ecom-formation_francecentral
  └── Snapshots (type: Microsoft.Compute/snapshots)
      ├── velero-*-postgres-data-postgres-0
      ├── velero-*-postgres-data-postgres-1
      └── velero-*-postgres-data-postgres-2
```

Ils sont visibles dans le portail Azure :  
**Home → Resource Groups → MC_rg-formation-ecom-aks_... → Snapshots**

Ou via CLI :
```bash
kubectl get volumesnapshotcontent
# READYTOUSE: true pour chaque PVC snapshottée
```

---

## Alternatives considérées

### Option A — Native disk snapshots via VSL ❌ (rejeté)

```yaml
# Ce qu'on ne peut PAS faire avec v1.11.0 + Workload Identity :
volumeSnapshotLocation:
  - name: default
    provider: azure
    config:
      useAAD: "true"  # INVALIDE en v1.11.0 — clé non reconnue
```

- **Problème :** Le VSL en v1.11.0 n'accepte pas `useAAD` — retourne `config has invalid keys [useAAD]`
- **Problème :** Sans `useAAD`, le VSL cherche `AZURE_SUBSCRIPTION_ID` dans un fichier credentials — incompatible avec notre setup zero-credentials
- **Décision : rejeté** — techniquement incompatible avec Workload Identity en v1.11.0

### Option B — Désactiver les snapshots de volumes ❌ (rejeté)

```yaml
snapshotVolumes: false  # backup manifests only
```

- **Problème :** On perd la sauvegarde des données PostgreSQL (PVCs 2 Gi × 3 replicas)
- **Problème :** En cas de DR, on restaure les pods mais sans les données — le cluster redémarre vide
- **Décision : rejeté explicitement** — « pourquoi désactive les pv snapshot, je perds ma donnée »

### Option C — kopia via node-agent (file-level backup) ❌ (non retenu pour PostgreSQL)

```yaml
# Backup des fichiers PV via kopia :
defaultVolumesToFsBackup: true
```

- **Problème :** Pour PostgreSQL, un backup au niveau fichier sans quiesce n'est pas crash-consistent — risque de corruption des fichiers WAL
- **Avantage :** Fonctionne sans CSI, supporte tout type de volume
- **Décision :** Gardé comme fallback documenté, non activé par défaut pour les PVCs PostgreSQL

### Option D — CSI Volume Snapshots ✅ (choisie)

- Utilise le driver CSI natif AKS (`disk.csi.azure.com`) — supporté depuis AKS 1.21+
- Snapshot **crash-consistent** au niveau disque (Azure Managed Disk Snapshot incrémental)
- Indépendant du mécanisme d'authentification VSL — le driver CSI utilise l'identité du node pool
- Incrémental (`incremental: "true"`) — seules les pages modifiées depuis le dernier snapshot sont copiées
- Entièrement transparent pour Velero via le label `velero.io/csi-volumesnapshot-class`
- Aucun rôle Azure supplémentaire requis (le driver CSI hérite des permissions du node pool)

---

## Conséquences

### Positives

- Snapshot crash-consistent pour PostgreSQL — pas de risque de corruption WAL
- Aucun credentials Azure supplémentaires requis pour les snapshots
- Snapshot incrémentaux — réduisent le temps de backup et le coût Azure Disk Snapshot
- Restauration automatique : Velero recrée les PVCs depuis les VolumeSnapshots lors d'un restore

### Négatives / Points de vigilance

- Les snapshots CSI sont stockés dans le Resource Group `MC_...` (node pool) — **pas** dans le `rg-formation-ecom-aks` principal. Ils ne sont pas visibles dans le portail Azure au même endroit que les autres ressources Velero
- La `VolumeSnapshotClass` `csi-azure-vsc` est appliquée **hors Terraform** (`kubectl apply`) — risque de drift si le cluster est recréé sans rejouer ce manifest
- `deletionPolicy: Retain` — les snapshots CSI survivent à la suppression du backup Velero. Nettoyage manuel requis si la rétention doit s'appliquer aussi aux snapshots disk
- En DR (nouveau cluster), les snapshots CSI du cluster source ne sont pas automatiquement accessibles — la restauration des PVCs doit s'appuyer sur les blobs Blob Storage (file-level via kopia) ou une procédure manuelle `pg_basebackup`

---

## Validation

```bash
# Vérifier que les snapshots CSI sont créés après un backup
kubectl get volumesnapshotcontent
# NAME                    READYTOUSE   DRIVER                  DELETIONPOLICY   ...
# velero-*-postgres-*     true         disk.csi.azure.com      Retain           ...

# Vérifier la VolumeSnapshotClass est bien labellisée
kubectl get volumesnapshotclass csi-azure-vsc -o yaml | grep velero
# velero.io/csi-volumesnapshot-class: "true"
```

---

## Références

- [Velero CSI Snapshots documentation](https://velero.io/docs/main/csi/)
- [AKS CSI Driver — Disk Snapshots](https://learn.microsoft.com/en-us/azure/aks/azure-disk-csi)
- [ADR-003 — Workload Identity](ADR-003-workload-identity.md)
- [ADR-001 — Choix de Velero](ADR-001-velero-backup-solution.md)