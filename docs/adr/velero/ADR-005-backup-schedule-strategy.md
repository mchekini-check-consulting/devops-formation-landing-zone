# ADR-005 — Stratégie de schedule de backup : double niveau cluster + namespace

| Champ      | Valeur                  |
|------------|-------------------------|
| Statut     | Accepté                 |
| Date       | 2026-05-30              |
| Auteur     | elGiordano              |
| Contexte   | Phase 04 — US Backup DR |

---

## Contexte

Velero permet de configurer des backups schedulés via des ressources `Schedule`. La granularité de backup (cluster entier vs. namespace vs. sélecteur de labels) détermine :
- La **rapidité du restore** (RTO) selon le type d'incident
- Le **coût de stockage** (taille des backups)
- La **complexité opérationnelle** (nombre de schedules à surveiller)

Les critères d'acceptation définissent deux types de schedules :
1. `daily-full-cluster` : cluster entier, 01:00 UTC, rétention 14 jours
2. `daily-<namespace>` : par namespace, rétention 7 jours

---

## Décision

Implémenter une **stratégie à double niveau** :

### Niveau 1 — Backup full cluster

| Paramètre               | Valeur                                  |
|-------------------------|-----------------------------------------|
| Nom                     | `daily-full-cluster`                    |
| Schedule                | `0 1 * * *` (01:00 UTC)                |
| Namespaces              | Tous (`*`)                              |
| Cluster resources       | `true` (CRDs, ClusterRoles, StorageClasses, PVs) |
| Snapshots de volumes    | `true`                                  |
| TTL (rétention)         | `336h` (14 jours)                       |
| Heure choisie           | 01:00 UTC = 03:00 Paris (creux d'activité) |

### Niveau 2 — Backup par namespace

| Paramètre               | Valeur                                   |
|-------------------------|------------------------------------------|
| Nom pattern             | `daily-<namespace>`                      |
| Schedules existants     | `daily-dev`, `daily-ingress-nginx`       |
| Schedule cron           | `30 1 * * *`, `45 1 * * *` (décalé)    |
| Cluster resources       | `false` (namespaced uniquement)          |
| Snapshots de volumes    | `true` pour `dev`, `false` pour `ingress-nginx` |
| TTL (rétention)         | `168h` (7 jours)                         |

**Décalage des heures :** les schedules namespace sont décalés de 30–45 minutes après le full-cluster pour éviter la contention sur le node-agent lors du backup simultané des volumes.

---

## Alternatives considérées

### Option A — Backup full cluster uniquement

```yaml
schedules:
  daily-full-cluster:
    schedule: "0 1 * * *"
    ttl: "336h"
    includedNamespaces: ["*"]
```

- **Avantages :**
  - Un seul schedule à surveiller
  - Cohérence garantie entre tous les namespaces au même instant
- **Problèmes :**
  - Restore d'un seul namespace = extraire du backup full (plus lent, plus de risques d'erreurs)
  - TTL unifié 14j pour tous les namespaces — coût plus élevé pour des namespaces à faible valeur
  - Impossible d'avoir des politiques de rétention différenciées par namespace
- **Décision : insuffisant** — ne couvre pas le critère "restaurer un seul namespace"

### Option B — Backup par namespace uniquement

```yaml
schedules:
  daily-dev:
    includedNamespaces: ["dev"]
  daily-ingress-nginx:
    includedNamespaces: ["ingress-nginx"]
```

- **Avantages :**
  - Restauration namespace granulaire rapide
  - Rétention différenciée possible
- **Problèmes :**
  - **Les ressources cluster-level ne sont pas sauvegardées** : CRDs, ClusterRoles, ClusterRoleBindings, PersistentVolumes (le PV est une ressource cluster, le PVC est namespace)
  - StorageClass `postgres-standard-ssd` non sauvegardée → restore impossible sans la recréer manuellement
  - En cas de DR complet, le restore namespace seul est insuffisant
- **Décision : insuffisant** — perd les ressources cluster-level critiques

### Option C — Double niveau cluster + namespace ✅ (choisie)

- Combine les avantages des deux options
- Le backup full-cluster couvre le scénario DR complet (cluster perdu)
- Les backups namespace permettent un restore rapide et granulaire d'un namespace en 5–10 minutes
- Les TTL différenciés optimisent le coût de stockage (namespace = 7j vs. full = 14j)
- Léger overhead de stockage compensé par le Cool tier low-cost

### Option D — Backup incrémentiel

- Velero ne supporte pas nativement les backups incrémentaux (chaque backup est complet)
- kopia (node-agent) gère le déduplication interne, ce qui réduit effectivement le stockage dans la pratique
- **Décision : non applicable** — pas de fonctionnalité native, kopia gère déjà la déduplication

### Option E — Backup basé sur des labels (sélecteur de ressources)

```yaml
labelSelector:
  matchLabels:
    backup: "true"
```

- **Problèmes :**
  - Nécessite d'annoter toutes les ressources à sauvegarder — risque d'oubli
  - Charge opérationnelle élevée : chaque nouvelle ressource doit être étiquetée
  - Le backup full-cluster garantit la complétude sans annotation
- **Décision : rejeté** — opérabilité insuffisante pour un backup de DR

---

## Détails de la planification horaire

```
00:00 UTC │
01:00 UTC │ ← daily-full-cluster commence (tous namespaces + volumes)
          │   Durée estimée : 10–20 min (volumes ~6 Gi)
01:30 UTC │ ← daily-dev commence (namespace dev, décalé)
01:45 UTC │ ← daily-ingress-nginx commence (namespace ingress-nginx, sans volumes)
03:00 UTC │ (fin probable de tous les backups)
```

Le choix de 01:00 UTC correspond à **03:00 heure de Paris** (CET/CEST), moment de faible activité pour minimiser l'impact sur les workloads.

---

## Extension future : ajout d'un nouveau namespace

Lorsqu'un nouveau namespace est ajouté au cluster, le processus est :

1. Ajouter un bloc dans `modules/platform/velero-values.yaml` :
   ```yaml
   daily-<nouveau-namespace>:
     schedule: "0 2 * * *"
     template:
       ttl: "168h"
       includedNamespaces: ["<nouveau-namespace>"]
   ```
2. `terraform apply` — Velero crée la ressource Schedule automatiquement

---

## Conséquences

### Positives

- RTO réduit pour les incidents namespace (restore en 5–10 min vs. 20–40 min pour un full)
- DR complet couvert par le backup full-cluster
- Coût de stockage optimisé via TTL différenciés (7j namespace vs. 14j full)
- Extensible : ajouter un namespace = une entrée dans le YAML

### Négatives / Points de vigilance

- Le backup full-cluster et les backups namespace créent une légère redondance de stockage
- Le node-agent est sollicité séquentiellement sur 45 minutes (mitigé par le décalage des schedules)
- Si un nouveau namespace est créé sans ajouter de schedule dédié, il est couvert uniquement par le full-cluster (14j)

---

## Références

- [Velero Schedule API](https://velero.io/docs/main/api-types/schedule/)
- [Velero resource filtering](https://velero.io/docs/main/resource-filtering/)
- [ADR-006 — Politique de rétention](ADR-006-retention-policy.md)
- [ADR-002 — Cool tier stockage](ADR-002-azure-blob-storage-cool-tier.md)