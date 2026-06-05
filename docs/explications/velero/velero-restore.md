# Procédures de restauration Velero

Ce document décrit les procédures de restauration du cluster AKS via Velero.  
Référencer les [ADRs de backup](adr/) pour le contexte des décisions d'architecture.

---

## Prérequis

```bash
# Vérifier que Velero est opérationnel
velero version
kubectl get pods -n velero

# Vérifier les backups disponibles
velero backup get

# Exemple de sortie attendue :
# NAME                               STATUS     ERRORS   WARNINGS   CREATED                         EXPIRES   STORAGE LOCATION   SELECTOR
# daily-full-cluster-20260530010000  Completed  0        0          2026-05-30 01:00:00 +0000 UTC   13d       default            <none>
# daily-dev-20260530013000           Completed  0        0          2026-05-30 01:30:00 +0000 UTC   6d        default            <none>
```

---

## 1. Restauration d'un namespace complet

**Scénario :** Le namespace `dev` a été supprimé accidentellement ou est corrompu.

### 1.1 Identifier le backup à utiliser

```bash
# Lister les backups disponibles pour le namespace dev
velero backup get | grep daily-dev

# Inspecter le contenu d'un backup spécifique
velero backup describe daily-dev-20260530013000 --details
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
  --from-backup daily-dev-20260530013000 \
  --include-namespaces dev \
  --wait
```

### 1.4 Vérifier la restauration

```bash
# Statut de la restauration
velero restore get

# Vérifier les ressources restaurées dans le namespace
kubectl get all -n dev
kubectl get pvc -n dev
kubectl get configmap -n dev
kubectl get secret -n dev

# Vérifier les pods en état Running
kubectl get pods -n dev -w
```

### 1.5 Restaurer aussi depuis le full-cluster si le namespace était absent > 7j

Si le backup namespace a expiré (> 7 jours), utiliser le backup full-cluster :

```bash
velero restore create restore-dev-from-full-$(date +%Y%m%d%H%M) \
  --from-backup daily-full-cluster-20260523010000 \
  --include-namespaces dev \
  --wait
```

---

## 2. Restauration d'une ressource spécifique

**Scénario :** Un Deployment, ConfigMap, ou PVC spécifique a été supprimé ou modifié incorrectement.

### 2.1 Identifier la ressource et le backup

```bash
# Lister les ressources dans un backup
velero backup describe daily-full-cluster-20260530010000 --details | grep -A5 "dev/"

# Ou chercher une ressource spécifique
velero backup describe daily-full-cluster-20260530010000 --details | grep "postgres"
```

### 2.2 Restauration d'un Deployment

```bash
velero restore create restore-postgres-deploy-$(date +%Y%m%d%H%M) \
  --from-backup daily-full-cluster-20260530010000 \
  --include-namespaces dev \
  --include-resources deployments \
  --selector app=postgres \
  --wait
```

### 2.3 Restauration d'un ConfigMap spécifique

```bash
velero restore create restore-cm-$(date +%Y%m%d%H%M) \
  --from-backup daily-full-cluster-20260530010000 \
  --include-namespaces dev \
  --include-resources configmaps \
  --selector app=postgres \
  --wait
```

### 2.4 Restauration d'un PVC et ses données

```bash
# Un PVC supprimé nécessite de restaurer aussi le PV (cluster-level)
velero restore create restore-pvc-$(date +%Y%m%d%H%M) \
  --from-backup daily-full-cluster-20260530010000 \
  --include-namespaces dev \
  --include-resources persistentvolumeclaims,persistentvolumes \
  --selector app=postgres \
  --restore-volumes=true \
  --wait

# Vérifier que le PVC est en état Bound
kubectl get pvc -n dev
```

### 2.5 Restauration avec écrasement (ressource existante mais corrompue)

```bash
# Par défaut Velero ne remplace pas les ressources existantes
# Utiliser --existing-resource-policy=update pour forcer la mise à jour
velero restore create restore-overwrite-$(date +%Y%m%d%H%M) \
  --from-backup daily-full-cluster-20260530010000 \
  --include-namespaces dev \
  --include-resources configmaps \
  --selector app=postgres \
  --existing-resource-policy=update \
  --wait
```

---

## 3. Restauration vers un autre cluster (scénario DR)

**Scénario :** Le cluster AKS principal est indisponible ou détruit. On restaure sur un nouveau cluster AKS dans une autre région ou le même Resource Group.

### 3.1 Prérequis sur le cluster cible

Le cluster cible doit avoir :
- Velero installé avec le **même backend de stockage** (même Storage Account Azure Blob)
- Le même plugin `velero-plugin-for-microsoft-azure`
- Une Workload Identity configurée avec accès en **lecture** au container `velero-backups`
- Les mêmes StorageClasses (ou un mapping de StorageClass configuré)

```bash
# Sur le cluster cible — vérifier que Velero voit les backups du cluster source
velero backup get
# Les backups du cluster source doivent apparaître (même BSL = même Blob container)
```

### 3.2 Vérifier la StorageClass disponible sur le cluster cible

```bash
kubectl get storageclass
# Le backup inclut la StorageClass "postgres-standard-ssd"
# Si elle n'existe pas sur le cluster cible, créer un mapping :
```

Si la StorageClass du cluster source (`postgres-standard-ssd`) n'existe pas sur le cluster cible :

```bash
# Option A : créer la StorageClass manuellement avant le restore
kubectl apply -f k8s/postgres/00-storageclass.yaml

# Option B : mapper vers une StorageClass existante lors du restore
velero restore create restore-dr-$(date +%Y%m%d%H%M) \
  --from-backup daily-full-cluster-20260530010000 \
  --storage-class-mappings "postgres-standard-ssd:managed-premium" \
  --wait
```

### 3.3 Restauration complète du cluster

```bash
# Restaurer toutes les ressources cluster + tous les namespaces
velero restore create restore-full-dr-$(date +%Y%m%d%H%M) \
  --from-backup daily-full-cluster-20260530010000 \
  --restore-volumes=true \
  --wait

# Suivre la progression
velero restore describe restore-full-dr-$(date +%Y%m%d%H%M) --details
```

### 3.4 Restauration sélective en DR (namespaces prioritaires)

Si le temps est critique, restaurer en priorité les namespaces essentiels :

```bash
# Étape 1 : namespaces critiques d'abord
velero restore create restore-dr-critical-$(date +%Y%m%d%H%M) \
  --from-backup daily-full-cluster-20260530010000 \
  --include-namespaces "ingress-nginx,dev" \
  --restore-volumes=true \
  --wait

# Étape 2 : vérifier les ingress et services exposés
kubectl get ingress -A
kubectl get svc -n ingress-nginx
```

### 3.5 Post-restauration DR : vérifications obligatoires

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
# Récupérer la nouvelle EXTERNAL-IP et mettre à jour les enregistrements DNS
```

---

## 4. Commandes de diagnostic utiles

```bash
# Voir les logs du serveur Velero
kubectl logs -n velero deployment/velero

# Voir les logs d'un backup spécifique
velero backup logs daily-full-cluster-20260530010000

# Voir les logs d'une restauration
velero restore logs restore-dev-20260530120000

# Voir les erreurs d'une restauration
velero restore describe restore-dev-20260530120000 | grep -A10 "Errors"

# Lister les BackupStorageLocations et leur statut
velero backup-location get

# Forcer un backup immédiat (hors schedule)
velero backup create manual-backup-$(date +%Y%m%d%H%M) \
  --include-namespaces "*" \
  --include-cluster-resources=true \
  --wait
```

---

## 5. Matrice des scénarios de restauration

| Scénario                             | Backup à utiliser         | Commande principale                                          | RTO estimé |
|--------------------------------------|---------------------------|--------------------------------------------------------------|------------|
| Namespace `dev` perdu (< 7j)         | `daily-dev-*`             | `--from-backup daily-dev-* --include-namespaces dev`         | 5–10 min   |
| Namespace `dev` perdu (7–14j)        | `daily-full-cluster-*`    | `--from-backup daily-full-cluster-* --include-namespaces dev`| 10–20 min  |
| Deployment/ConfigMap supprimé        | `daily-full-cluster-*`    | `--include-resources deployments --selector app=X`           | 2–5 min    |
| PVC perdu + données                  | `daily-full-cluster-*`    | `--include-resources pvc,pv --restore-volumes=true`          | 15–30 min  |
| Cluster complet perdu (DR)           | `daily-full-cluster-*`    | Restore complet + vérifications post-restore                 | 45–90 min  |
| NGINX Ingress supprimé               | `daily-ingress-nginx-*`   | `--include-namespaces ingress-nginx`                         | 5 min      |
| Cluster corrompu (rollback config)   | `daily-full-cluster-*`    | `--existing-resource-policy=update`                          | 20–40 min  |