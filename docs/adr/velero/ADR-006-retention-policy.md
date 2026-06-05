# ADR-006 — Politique de rétention des backups : 14 jours / 7 jours

| Champ      | Valeur                  |
|------------|-------------------------|
| Statut     | Accepté                 |
| Date       | 2026-05-30              |
| Auteur     | elGiordano              |
| Contexte   | Phase 04 — US Backup DR |

---

## Contexte

La rétention des backups Velero détermine :
- La **fenêtre de RPO (Recovery Point Objective)** maximale : jusqu'où dans le passé peut-on restaurer ?
- Le **coût de stockage** : plus la rétention est longue, plus le stockage Azure Blob augmente
- La **détection tardive des incidents** : certaines corruptions ou suppressions accidentelles ne sont détectées que plusieurs jours après

Les critères d'acceptation définissent :
- **Backup full cluster** : rétention **14 jours**
- **Backup par namespace** : rétention **7 jours**

---

## Décision

Appliquer les TTL (Time-To-Live) Velero suivants, traduits en heures :

| Schedule              | TTL Velero | Durée |
|-----------------------|------------|-------|
| `daily-full-cluster`  | `336h`     | 14 jours |
| `daily-dev`           | `168h`     | 7 jours  |
| `daily-ingress-nginx` | `168h`     | 7 jours  |

La rétention est gérée par Velero nativement via le champ `.spec.template.ttl` de la ressource `Schedule`. Velero supprime automatiquement les backups expirés du Blob Storage lors du garbage collection quotidien.

En complément, une **lifecycle policy Azure Blob** supprime définitivement tout objet modifié depuis plus de 45 jours — filet de sécurité si le garbage collection Velero échoue.

---

## Alternatives considérées

### Durée trop courte : 3 jours

- **Problème :** Certains incidents (corruption silencieuse de données, suppression graduelle par un bug applicatif) ne sont détectés qu'après plusieurs jours. Une fenêtre de 3 jours ferme la possibilité de restaurer dans la plupart des scénarios réels.
- **Décision : rejeté** — fenêtre RPO insuffisante

### 7 jours pour tout (sans différenciation)

- **Avantage :** Simple, un seul paramètre
- **Problème :**
  - Le full-cluster avec 7j expose à un risque plus élevé : un incident détecté après une semaine ne permet pas de restaurer à un état stable antérieur
  - Les CRDs, ClusterRoles, PersistentVolumes (cluster-level) sont plus longs à recréer manuellement — la rétention plus longue du full-cluster est justifiée par cette criticité
- **Décision : rejeté** — rétention insuffisante pour le backup full-cluster

### 14 jours pour tout (uniformisation à la hausse)

- **Avantage :** RPO maximal pour tous les backups
- **Problème :**
  - Les backups namespace stockent à la fois les manifests ET les snapshots de volumes
  - Un backup namespace de 14j pour un namespace `dev` avec 6 Gi de volumes = ~84 Gi de rétention
  - Sur Cool tier : ~84 Gi × 0,010 €/Go = ~0,84 €/mois uniquement pour les namespaces
  - En pratique, la perte d'un namespace isolé est récupérable depuis le full-cluster au-delà de 7j
- **Décision : acceptable mais non optimal** — coût supérieur sans bénéfice opérationnel clair

### 30 jours

- **Contexte :** Standard dans certaines organisations pour conformité RGPD ou audits internes
- **Problème :**
  - Ce projet est un **environnement de formation**, pas un système de production avec contraintes réglementaires
  - 30 jours multiplierait le coût de stockage par ~2 comparé à 14j
  - La valeur marginale des backups entre J+14 et J+30 est quasi-nulle dans ce contexte
- **Décision : rejeté** — coût disproportionné pour l'environnement cible

### 14 jours full / 7 jours namespace ✅ (choisie)

**Raisonnement :**

**Pourquoi 14 jours pour le full-cluster ?**
- La plupart des incidents de corruption ou suppression accidentelle d'objets cluster-level (CRDs, ClusterRoles) sont détectés dans les 24–72h via alerting (Prometheus, Azure Monitor)
- 14 jours offre une marge confortable pour les weekends, congés, et incidents détectés tardivement
- Cohérent avec les standards SRE (SLO de backup généralement aligné sur 2 semaines)
- Sur Cool tier, le coût pour ~14 × 2 Gi de backup ≈ 0,30 €/mois — négligeable

**Pourquoi 7 jours pour les namespaces ?**
- Un namespace perdu (`dev`) est récupérable depuis le full-cluster au-delà de 7j
- Les backups namespace servent prioritairement au **restore rapide** d'un incident récent (< 7j)
- Réduit le coût et la redondance de stockage
- 7 jours couvre la fenêtre standard d'un sprint (équipe qui travaille en sprints d'une semaine)

---

## Impact coût estimé

| Backup type         | Taille estimée/backup | Rétention | Total stockage | Coût Cool (~0,010 €/Go) |
|---------------------|-----------------------|-----------|----------------|--------------------------|
| full-cluster (daily)| ~2 Gi                 | 14 j      | ~28 Gi         | ~0,28 €/mois             |
| daily-dev           | ~1 Gi                 | 7 j       | ~7 Gi          | ~0,07 €/mois             |
| daily-ingress-nginx | ~50 Mi                | 7 j       | ~350 Mi        | ~0,004 €/mois            |
| **Total**           |                       |           | **~35 Gi**     | **~0,35 €/mois**         |

*Note : kopia déduplique les blocs identiques entre backups successifs — le stockage réel est probablement 30–50 % inférieur à cette estimation brute.*

---

## Mécanisme de nettoyage

Deux mécanismes assurent la suppression des backups expirés :

1. **Velero garbage collector** : tourne quotidiennement, supprime les backups dont le TTL est dépassé en les marquant `Deleting` et en supprimant les objets Blob correspondants
2. **Azure Blob lifecycle policy** (filet de sécurité) : supprime tout blob modifié il y a plus de 45 jours, indépendamment de Velero — protège contre un bug de garbage collection

---

## Conséquences

### Positives

- RPO de 14 jours pour les scénarios DR complets
- Coût de stockage minimal (~0,35 €/mois estimé)
- Nettoyage automatique — aucune intervention manuelle pour la rotation des backups
- Différenciation pertinente : namespace (court terme / restore rapide) vs. cluster (long terme / DR)

### Négatives / Points de vigilance

- Un incident non détecté après 14 jours ne pourra pas être restauré depuis les backups Velero (nécessiterait un snapshot Azure Disk indépendant pour aller plus loin)
- Si le volume de données PVC augmente significativement (ex : PostgreSQL avec des données réelles > 50 Gi), revoir la rétention namespace à la baisse ou le tier de stockage

---

## Références

- [Velero TTL and expiration](https://velero.io/docs/main/how-velero-works/#set-a-backup-expiration)
- [Velero garbage collection](https://velero.io/docs/main/garbage-collection/)
- [ADR-002 — Azure Blob Cool tier](ADR-002-azure-blob-storage-cool-tier.md)
- [ADR-005 — Stratégie de schedule](ADR-005-backup-schedule-strategy.md)