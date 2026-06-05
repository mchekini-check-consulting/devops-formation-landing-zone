# ADR-002 — Azure Blob Storage Standard LRS Cool tier

| Champ      | Valeur                  |
|------------|-------------------------|
| Statut     | Accepté                 |
| Date       | 2026-05-30              |
| Auteur     | elGiordano              |
| Contexte   | Phase 04 — US Backup DR |

---

## Contexte

Velero nécessite un backend de stockage objet pour persister les backups (manifests sérialisés en JSON + données de volumes compressées via kopia). Sur Azure, le plugin officiel supporte **Azure Blob Storage**.

Le projet suit une stratégie explicitement **low-cost** :
- ACR en tier Standard (pas Premium)
- PostgreSQL sur `StandardSSD_LRS` (pas Premium SSD)
- AKS en nœuds `Standard_B2s_v2` (burstable)
- Terraform state en `Standard_LRS`

Les backups Velero ont un profil d'accès particulier : **écriture quotidienne, lecture rare** (seulement en cas d'incident ou de DR). Ce profil est idéal pour un tier de stockage froid.

---

## Décision

Utiliser **Azure Blob Storage Standard LRS en tier Cool** pour le backend Velero, avec une **lifecycle policy** qui bascule en Archive après 30 jours et supprime après 45 jours.

```
Écriture  : daily (velero backup → blob upload)
Lecture   : rare (restauration en cas d'incident)
Tier      : Cool
SKU       : Standard_LRS
Rétention : 14j (full-cluster) / 7j (namespace) via TTL Velero
Lifecycle : → Archive après 30j → Delete après 45j (sécurité)
```

---

## Alternatives considérées

### Tier Hot

- Accès en lecture/écriture optimal, aucune latence de réhydratation
- **Coût stockage** : ~0,018 €/Go/mois (France Central)
- **Problème :** Pour des backups rarement lus, payer le double du stockage n'est pas justifié
- **Décision : rejeté** — surdimensionné pour ce profil d'accès

### Tier Cool ✅ (choisie)

- **Coût stockage** : ~0,010 €/Go/mois (~45 % moins cher que Hot)
- Frais d'accès en lecture : ~0,01 €/10 000 opérations (négligeable pour un usage rare)
- Disponibilité SLA : 99,9 % (identique à Hot)
- Accès immédiat (pas de délai de réhydratation)
- **Parfait** pour le profil backup : écriture fréquente, lecture rare

### Tier Archive

- **Coût stockage** : ~0,001 €/Go/mois (10x moins cher que Cool)
- **Problème critique :** Réhydratation requise avant lecture (6 à 15 heures en priorité standard)
  - Un incident à 02:00 UTC avec besoin de restore immédiat est bloqué pendant 6–15h
  - Incompatible avec un RTO acceptable pour un environnement de production
- **Mitigation possible** : réhydratation en priorité haute (~1h) mais coût très élevé à l'usage
- **Décision : rejeté** — RTO inacceptable pour les backups récents

### GRS / ZRS (redondance géographique ou zonale)

- **GRS** (Geo-Redundant Storage) : réplication dans une région secondaire
- **ZRS** (Zone-Redundant Storage) : réplication dans 3 zones de disponibilité
- **Coût** : +50 % à +100 % par rapport à LRS
- **Analyse :**
  - Les backups ne sont pas des données primaires — leur perte n'est pas un SPOF si la sauvegarde elle-même est correctement retenue (14 jours)
  - En cas de DR complet de la région Azure France Central, le scénario DR Velero vers un autre cluster est déjà documenté
  - `StandardSSD_LRS` est déjà le choix du reste du projet
- **Décision : rejeté** — surcoût non justifié, cohérent avec la stratégie LRS du projet

### Azure Files

- Service de fichiers managé Azure (SMB/NFS)
- **Problème :** Velero plugin for Azure supporte uniquement **Blob Storage** comme backend (pas Azure Files)
- **Décision : rejeté** — non supporté par le plugin

### Compte de stockage dédié vs. partage

- Option : réutiliser le compte de stockage du Terraform state (`sanecomformation`)
- **Problème :**
  - Mélanger l'état Terraform et les backups Velero dans le même compte crée un SPOF opérationnel
  - Risque accidentel : suppression ou modification des containers lors d'opérations Terraform
  - Impossible de différencier les politiques d'accès (IAM) sans complexité inutile
- **Décision : compte dédié** `stvelero<team_name>` — isolation claire des responsabilités

---

## Estimation de coût

Pour un cluster de taille formation (quelques namespaces, PVCs de ~2 Gi chacun) :

| Élément                         | Estimation        |
|---------------------------------|-------------------|
| Manifests sérialisés par backup | ~5–20 Mo          |
| Volume backup (3 PVCs × 2 Gi)  | ~500 Mo–2 Go       |
| Rétention 14 jours (full)       | ~14 × 2 Go = 28 Go|
| Rétention 7 jours (namespace)   | ~7 × 200 Mo = 1.4 Go |
| **Coût stockage Cool LRS**      | **~0,30 €/mois**  |

Le coût est négligeable comparé à l'infrastructure AKS existante.

---

## Conséquences

### Positives

- Cohérence avec la stratégie de coût du projet (tout en LRS, tier économique)
- RTO compatible avec le tier Cool (accès immédiat)
- Lifecycle policy automatique évite l'accumulation indéfinie si TTL Velero est contourné
- Soft delete (7 jours) sur le blob container protège contre la suppression accidentelle

### Négatives / Points de vigilance

- Les opérations de lecture en tier Cool ont un coût unitaire (minime, négligeable pour ce volume)
- Si le volume de données PV augmente significativement (plusieurs dizaines de Go), reconsidérer Hot pour les 7 derniers jours et Cool pour les plus anciens via tiering automatique

---

## Références

- [Azure Blob Storage pricing (France Central)](https://azure.microsoft.com/fr-fr/pricing/details/storage/blobs/)
- [Azure Blob lifecycle management](https://learn.microsoft.com/fr-fr/azure/storage/blobs/lifecycle-management-overview)
- [ADR-006 — Politique de rétention](ADR-006-retention-policy.md)