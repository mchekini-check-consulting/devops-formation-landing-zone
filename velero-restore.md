# Procédures de restauration Velero

Ce document décrit les procédures de restauration du cluster AKS via Velero.  
Référencer les [ADRs de backup](../../adr/velero/) pour le contexte des décisions d'architecture.

---

## Runbook — Test manuel de backup et restore

Ce runbook décrit la procédure complète pour valider qu'un backup automatique ou manuel peut être restauré avec succès. À exécuter après chaque changement de configuration Velero, ou pour valider la procédure DR.

### Étape 1 — Vérifier l'état de Velero

```bash
# Velero server et node-agent en Running
kubectl get pods -n velero

# BSL disponible (Workload Identity fonctionnel)
velero backup-location get
# NAME      PROVIDER   BUCKET/PREFIX    PHASE       ...
# default   azure      velero-backups   Available   ...

# Schedule actif
velero schedule get
# NAME        STATUS    SCHEDULE      ...
# daily-dev   Enabled   30 1 * * *    ...
```

### Étape 2 — Déclencher un backup manuel

```bash
BACKUP_NAME="test-restore-$(date +%Y%m%d%H%M)"

velero backup create $BACKUP_NAME \
  --include-namespaces dev \
  --snapshot-volumes=true \
  -n velero \
  --wait

# Vérifier le statut
velero backup describe $BACKUP_NAME -n velero
# Phase: Completed (pas PartiallyFailed)
```

### Étape 3 — Vérifier les snapshots CSI des PVCs

```bash
# Les snapshots CSI doivent être READYTOUSE: true pour les 3 PVCs postgres
kubectl get volumesnapshotcontent
# NAME                    READYTOUSE   DRIVER                  ...
# velero-*-postgres-0     true         disk.csi.azure.com      ...
# velero-*-postgres-1     true         disk.csi.azure.com      ...
# velero-*-postgres-2     true         disk.csi.azure.com      ...

# Lister les backups disponibles
velero backup get
```

> Les snapshots CSI sont visibles dans le portail Azure :  
> **Home → Resource Groups → MC_rg-formation-ecom-aks_aks-ecom-formation_francecentral → Snapshots**

### Étape 4 — Simuler le désastre (supprimer le namespace)

```bash
# Supprimer le namespace dev et tout son contenu
kubectl delete namespace dev

# Attendre la suppression complète (~1–2 min)
kubectl get namespace dev
# Error from server (NotFound): namespaces "dev" not found
```

### Étape 5 — Restaurer depuis le backup

```bash
velero restore create restore-$BACKUP_NAME \
  --from-backup $BACKUP_NAME \
  --include-namespaces dev \
  -n velero \
  --wait
```

### Étape 6 — Vérifier la restauration

```bash
# Statut de la restauration
velero restore describe restore-$BACKUP_NAME -n velero
# Phase: Completed

# Pods en Running
kubectl get pods -n dev

# PVCs en Bound (les données PostgreSQL sont restaurées depuis les snapshots CSI)
kubectl get pvc -n dev
# NAME                    STATUS   VOLUME   ...
# postgres-data-postgres-0  Bound    ...
# postgres-data-postgres-1  Bound    ...
# postgres-data-postgres-2  Bound    ...

# ConfigMaps et Secrets présents
kubectl get configmap -n dev
kubectl get secret -n dev

# Tester l'accès à PostgreSQL
kubectl exec -n dev postgres-0 -- psql -U postgres -c "SELECT version();"
kubectl exec -n dev postgres-0 -- psql -U postgres -c "\l"
```

### Étape 7 — Nettoyer après le test

```bash
# Supprimer le backup de test (libère aussi les snapshots CSI si deletionPolicy=Delete)
# Note: notre VolumeSnapshotClass utilise deletionPolicy: Retain
# Les snapshots CSI doivent être nettoyés manuellement si nécessaire
velero backup delete $BACKUP_NAME -n velero --confirm
```

---

## Procédure de restore après un backup automatique

Le schedule `daily-dev` déclenche un backup à **01:30 UTC** chaque nuit, avec une rétention de **7 jours**.

### Identifier le backup à utiliser

```bash
# Lister les backups disponibles
velero backup get
# NAME                 STATUS      ERRORS   WARNINGS   CREATED                         EXPIRES
# daily-dev-20260605013000  Completed  0        0     2026-06-05 01:30:00 +0000 UTC   6d

# Inspecter un backup pour vérifier son contenu
velero backup describe daily-dev-20260605013000 --details
```

### Restaurer le namespace dev depuis le dernier backup automatique

```bash
# Identifier le dernier backup completed
LATEST=$(velero backup get -o json | jq -r '[.items[] | select(.metadata.name | startswith("daily-dev")) | select(.status.phase=="Completed")] | sort_by(.metadata.creationTimestamp) | last | .metadata.name')
echo "Backup à utiliser : $LATEST"

# Supprimer l'environnement corrompu (si applicable)
kubectl delete namespace dev
kubectl get namespace dev  # attendre NotFound

# Lancer la restauration
velero restore create restore-$(date +%Y%m%d%H%M) \
  --from-backup $LATEST \
  --include-namespaces dev \
  -n velero \
  --wait
```

---

## 1. Restauration d'un namespace complet

**Scénario :** Le namespace `dev` a été supprimé accidentellement ou est corrompu.

### 1.1 Identifier le backup à utiliser

```bash
velero backup get | grep daily-dev

# Inspecter le contenu d'un backup spécifique
velero backup describe daily-dev-20260605013000 --details
```

### 1.2 Vérifier que le namespace est absent ou vide

```bash
kubectl get namespace dev
# Si le namespace existe et contient des ressources corrompues, le supprimer :
kubectl delete namespace dev
# Attendre la suppression complète (~1–2 min)
kubectl get namespace dev  # doit retourner "Error from server (NotFound)"
```

### 1.3 Lancer la restauration

```bash
velero restore create restore-dev-$(date +%Y%m%d%H%M) \
  --from-backup daily-dev-20260605013000 \
  --include-namespaces dev \
  --wait
```

### 1.4 Vérifier la restauration

```bash
velero restore get

kubectl get all -n dev
kubectl get pvc -n dev
kubectl get configmap -n dev
kubectl get secret -n dev

# Vérifier les pods en état Running
kubectl get pods -n dev -w
```

---

## 2. Restauration d'une ressource spécifique

**Scénario :** Un Deployment, ConfigMap, ou PVC spécifique a été supprimé ou modifié incorrectement.

### 2.1 Identifier la ressource et le backup

```bash
velero backup describe daily-dev-20260605013000 --details | grep "dev/"
velero backup describe daily-dev-20260605013000 --details | grep "postgres"
```

### 2.2 Restauration d'un Deployment

```bash
velero restore create restore-postgres-deploy-$(date +%Y%m%d%H%M) \
  --from-backup daily-dev-20260605013000 \
  --include-namespaces dev \
  --include-resources deployments \
  --selector app=postgres \
  --wait
```

### 2.3 Restauration d'un ConfigMap spécifique

```bash
velero restore create restore-cm-$(date +%Y%m%d%H%M) \
  --from-backup daily-dev-20260605013000 \
  --include-namespaces dev \
  --include-resources configmaps \
  --selector app=postgres \
  --wait
```

### 2.4 Restauration d'un PVC et ses données (CSI)

Avec les CSI snapshots, Velero recrée automatiquement les PVCs depuis les `VolumeSnapshot` inclus dans le backup — aucun flag supplémentaire n'est nécessaire :

```bash
velero restore create restore-pvc-$(date +%Y%m%d%H%M) \
  --from-backup daily-dev-20260605013000 \
  --include-namespaces dev \
  --include-resources persistentvolumeclaims,persistentvolumes \
  --selector app=postgres \
  --wait

# Vérifier que le PVC est en état Bound
kubectl get pvc -n dev
```

### 2.5 Restauration avec écrasement (ressource existante mais corrompue)

```bash
velero restore create restore-overwrite-$(date +%Y%m%d%H%M) \
  --from-backup daily-dev-20260605013000 \
  --include-namespaces dev \
  --include-resources configmaps \
  --selector app=postgres \
  --existing-resource-policy=update \
  --wait
```

---

## 3. Restauration vers un autre cluster (scénario DR)

**Scénario :** Le cluster AKS principal est indisponible ou détruit. On restaure sur un nouveau cluster AKS.

### 3.1 Prérequis sur le cluster cible

Le cluster cible doit avoir :
- Velero installé avec le **même backend de stockage** (même Storage Account Azure Blob `stveleroformation`, même container `velero-backups`)
- Le même plugin `velero-plugin-for-microsoft-azure` v1.11.0
- Une Workload Identity configurée avec accès `Storage Blob Data Contributor` sur `stveleroformation`
- La `VolumeSnapshotClass` `csi-azure-vsc` déployée : `kubectl apply -f k8s/velero/volumesnapshotclass.yaml`

```bash
# Sur le cluster cible — vérifier que Velero voit les backups du cluster source
velero backup get
# Les backups du cluster source doivent apparaître (même BSL = même Blob container)
```

> **Note CSI en DR :** Les snapshots CSI (`disk.csi.azure.com`) sont des Azure Managed Disk Snapshots stockés dans le Resource Group `MC_...` du cluster **source**. En DR, ces snapshots ne sont pas accessibles depuis le nouveau cluster. Pour restaurer les données PostgreSQL sur un cluster différent, utiliser `pg_basebackup` depuis un replica actif, ou activer le backup file-level via kopia (`defaultVolumesToFsBackup: true`) en complément des CSI snapshots.

### 3.2 Vérifier la StorageClass disponible sur le cluster cible

```bash
kubectl get storageclass
# Si la StorageClass "postgres-standard-ssd" n'existe pas, la créer avant le restore :
kubectl apply -f k8s/postgres/00-storageclass.yaml
```

### 3.3 Restauration du namespace dev

```bash
velero restore create restore-dr-$(date +%Y%m%d%H%M) \
  --from-backup daily-dev-20260605013000 \
  --include-namespaces dev \
  --wait
```

### 3.4 Post-restauration DR : vérifications obligatoires

```bash
# 1. Vérifier l'état de tous les pods
kubectl get pods -A | grep -v Running | grep -v Completed

# 2. Vérifier les PVCs sont Bound
kubectl get pvc -A | grep -v Bound

# 3. Vérifier PostgreSQL (StatefulSet)
kubectl get statefulset -n dev
kubectl exec -n dev postgres-0 -- psql -U postgres -c "SELECT version();"

# 4. Vérifier les secrets sont présents (Velero restaure les Secrets K8s)
kubectl get secrets -n dev

# 5. Mettre à jour le DNS si l'IP du LoadBalancer ingress a changé
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

---

## 4. Commandes de diagnostic utiles

```bash
# Voir les logs du serveur Velero
kubectl logs -n velero deployment/velero

# Voir les logs d'un backup spécifique
velero backup logs daily-dev-20260605013000

# Voir les logs d'une restauration
velero restore logs restore-dev-20260605120000

# Voir les erreurs d'une restauration
velero restore describe restore-dev-20260605120000 | grep -A10 "Errors"

# Lister les BackupStorageLocations et leur statut
velero backup-location get

# Vérifier les snapshots CSI présents
kubectl get volumesnapshotcontent
kubectl get volumesnapshot -n dev

# Forcer un backup immédiat du namespace dev
velero backup create manual-dev-$(date +%Y%m%d%H%M) \
  --include-namespaces dev \
  --snapshot-volumes=true \
  --wait

# Lister et supprimer un backup
velero backup get
velero backup delete <backup-name> --confirm
```

---

## 5. Matrice des scénarios de restauration

| Scénario                            | Backup à utiliser   | Commande principale                                          | RTO estimé |
|-------------------------------------|---------------------|--------------------------------------------------------------|------------|
| Namespace `dev` perdu (< 7j)        | `daily-dev-*`       | `--from-backup daily-dev-* --include-namespaces dev`         | 5–10 min   |
| Deployment/ConfigMap supprimé       | `daily-dev-*`       | `--include-resources deployments --selector app=X`           | 2–5 min    |
| PVC perdu + données (CSI)           | `daily-dev-*`       | `--include-resources pvc,pv` (CSI recrée depuis snapshot)    | 10–20 min  |
| Namespace perdu > 7j (expiré)       | N/A                 | Pas de backup disponible — reconstruire manuellement         | —          |
| Cluster complet perdu (DR)          | `daily-dev-*`       | Restore namespace + pg_basebackup pour les données PG        | 45–90 min  |
| Config corrompue (rollback)         | `daily-dev-*`       | `--existing-resource-policy=update`                          | 5–15 min   |