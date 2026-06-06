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

### VSL et CSI sont deux chemins indépendants

Ces deux mécanismes ne se partagent **rien** — ni le driver, ni la `VolumeSnapshotClass`, ni le mécanisme d'authentification :

```
VSL (volumeSnapshotLocation)
    └─ velero-plugin-for-microsoft-azure appelle l'API Azure Disk directement
       → NE passe PAS par le CSI driver
       → NE lit PAS la VolumeSnapshotClass
       → authentification via credentials file (incompatible Workload Identity en v1.11.0)

CSI (configuration.features: EnableCSI + VolumeSnapshotClass)
    └─ Velero crée un objet VolumeSnapshot K8s
       → le CSI controller lit la VolumeSnapshotClass csi-azure-vsc
       → disk.csi.azure.com appelle l'API Azure Disk
       → authentification via kubelet identity du node pool (automatique)
```

Le bloc `volumeSnapshotLocation` présent dans `velero-values.yaml` est **ignoré** pour nos PVCs PostgreSQL dès lors que `EnableCSI` est actif et que le provisioner des PVCs est `disk.csi.azure.com`. Velero choisit automatiquement le chemin CSI pour tout volume dont le driver est CSI. Le VSL ne serait invoqué que pour des volumes avec un driver non-CSI (ancien in-tree), absent de ce cluster.

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

### Pourquoi les snapshots CSI sont crash-consistent

Un snapshot est dit **crash-consistent** quand il capture l'état du disque tel qu'il serait après un crash brutal — toutes les pages disque figées au **même instant**.

PostgreSQL écrit en permanence sur deux fichiers liés :
- les **fichiers de données** (`/var/lib/postgresql/data/base/...`)
- les **WAL** (Write-Ahead Log — journal de transactions dans `pg_wal/`)

Un snapshot disque Azure fige toutes les pages atomiquement — exactement comme si la VM avait crashé à cet instant. PostgreSQL sait récupérer depuis cet état via son crash recovery (replay des WAL au démarrage). C'est suffisant sans avoir besoin d'un `CHECKPOINT` applicatif avant le snapshot.

À l'opposé, kopia (file-level) copie les fichiers **séquentiellement** :

```
kopia copie fichier par fichier :
  t=0 : copie data/base/.../1259   (page 7 = version A)
  t=1 : PostgreSQL modifie la page 7 (version B)
  t=2 : copie pg_wal/000001        (WAL référence version B)
  → data=A mais WAL=B → incohérence → corruption garantie
```

Le snapshot disque (CSI) capture tout en une seule opération atomique — pas de risque de décalage entre data et WAL.

---

### Ressources K8s créées

**`k8s/velero/volumesnapshotclass.yaml`** (appliqué manuellement via `kubectl apply`) :

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: csi-azure-vsc
  labels:
    velero.io/csi-volumesnapshot-class: "true"  # Velero utilise cette classe pour ses snapshots CSI
driver: disk.csi.azure.com                       # driver qui crée le snapshot physique Azure
deletionPolicy: Retain                           # snapshot Azure survit si la CR K8s est supprimée
parameters:
  incremental: "true"                            # seules les pages modifiées sont copiées
```

**Explication des champs clés :**

- **`driver`** — quel CSI driver crée le snapshot physique. `disk.csi.azure.com` est installé sur chaque nœud AKS par défaut.
- **`deletionPolicy: Retain`** — si le `VolumeSnapshot` K8s est supprimé, le snapshot Azure Disk **survit**. Avec `Delete`, la suppression de la CR déclenche la suppression du snapshot Azure (utile pour la rétention automatique — à envisager en production).
- **`incremental: "true"`** — Azure ne copie que les pages modifiées depuis le dernier snapshot. Un disque de 2 Gi avec peu de changements peut générer un snapshot de quelques Mo seulement.
- **`velero.io/csi-volumesnapshot-class: "true"`** — sans ce label, Velero ignore cette classe et ne sait pas quoi utiliser. C'est le seul moyen pour Velero de découvrir quelle `VolumeSnapshotClass` utiliser.

**Cycle de vie complet — création, rétention et suppression :**

```
Velero backup create
    │
    ├─ crée VolumeSnapshot (namespaced, dans "dev")
    │       │
    │       └─ CSI controller lit VolumeSnapshotClass "csi-azure-vsc"
    │               │
    │               └─ disk.csi.azure.com appelle Azure API
    │                       │
    │                       └─ crée Azure Managed Disk Snapshot (dans MC_...)
    │                               │
    │                               └─ retourne snapshotHandle (ID Azure)
    │
    └─ crée VolumeSnapshotContent (cluster-level)
            └─ stocke snapshotHandle
            └─ status.readyToUse = true

Velero backup expire (J+14)
    │
    └─ supprime VolumeSnapshot
            │
            └─ deletionPolicy: Delete → supprime VolumeSnapshotContent
                    │
                    └─ disk.csi.azure.com supprime le snapshot Azure dans MC_...

Au restore :
    Velero lit le VolumeSnapshotContent
    → disk.csi.azure.com recrée un disque Azure depuis le snapshot
    → le PVC est recréé avec les données PostgreSQL intactes
```

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