# ADR-001 — Choix de Velero comme solution de backup Kubernetes

| Champ      | Valeur                  |
|------------|-------------------------|
| Statut     | Accepté                 |
| Date       | 2026-05-30              |
| Auteur     | lamine                     |
| Contexte   | Phase 04 — US Backup DR |

---

## Contexte

Le cluster AKS héberge :
- Un StatefulSet PostgreSQL (3 replicas, PVCs `StandardSSD_LRS` 2 Gi chacun)
- Un contrôleur NGINX Ingress (namespace `ingress-nginx`)
- Des workloads applicatifs dans le namespace `dev`

En cas de désastre (suppression accidentelle, corruption, incident AKS, DR vers un autre cluster), il faut être en mesure de restaurer :
1. L'intégralité des manifests Kubernetes (Deployments, Services, ConfigMaps, PVCs, CRDs, ClusterRoles, etc.)
2. Les données persistantes stockées dans les PersistentVolumes

Aucune solution de backup n'est actuellement en place. Le projet suit une **stratégie low-cost** (visible dans `terraform.tfvars` et le choix `StandardSSD_LRS` pour PostgreSQL).

---

## Décision

**Utiliser Velero** (anciennement Heptio Ark), maintenu par VMware Tanzu, comme solution de backup et de restauration du cluster Kubernetes.

---

## Alternatives considérées

### Option A — Velero ✅ (choisie)

- Open source (Apache 2.0), maintenu activement par VMware Tanzu
- Plugin officiel `velero-plugin-for-microsoft-azure` — support natif Azure Blob + Azure Disk Snapshots
- Supporte le **Workload Identity** (zero-credentials) depuis la version 1.12
- Granularité de restore : cluster entier, namespace, ressource individuelle, sélecteur de labels
- Restore vers un cluster différent (scénario DR) supporté nativement
- Backup des volumes via **kopia** (node-agent) sans agent applicatif
- Helm chart officiel — cohérent avec l'approche d'installation existante (ingress-nginx)
- **Coût** : gratuit (open source)

### Option B — Azure Backup for AKS

- Solution managée Microsoft, intégration native Azure
- **Problèmes :**
  - En GA depuis 2024 mais couverture incomplète (certains types de ressources non supportés)
  - Coût significatif : facturation par instance protégée + stockage
  - Vendor lock-in fort : restore uniquement vers AKS Azure
  - Pas de restore vers un cluster non-Azure (DR limité)
  - Pas de restore granulaire par ressource individuelle au moment de l'évaluation
- **Décision : rejeté** — coût et limitations de restore incompatibles avec les critères d'acceptation

### Option C — Kasten K10 (Veeam)

- Solution enterprise très complète, UI graphique, DR avancé
- **Problèmes :**
  - Licence payante (pas de tier gratuit utilisable en production)
  - Complexité d'installation excessive pour ce contexte de formation
- **Décision : rejeté** — hors budget

### Option D — Snapshot etcd natif

- Backup direct de la base etcd du control plane AKS
- **Problèmes :**
  - Sur AKS, le control plane est managé par Microsoft — accès direct à etcd non disponible
  - Ne couvre pas les PersistentVolumes
  - Restore nécessite un accès au control plane (impossible sur AKS managé)
- **Décision : rejeté** — techniquement impossible sur AKS

### Option E — Export kubectl + scripts

- Scripts `kubectl get -o yaml` pour exporter les manifests, backup Azure Files/Disk séparé
- **Problèmes :**
  - Fragile : gestion manuelle des secrets, resources order, namespaces, CRDs
  - Pas de cohérence transactionnelle au moment du backup
  - Restore manuel complexe et source d'erreurs
  - Pas de scheduling natif, pas de rétention automatique
- **Décision : rejeté** — opérabilité insuffisante

---

## Conséquences

### Positives

- Outil standard de l'écosystème Kubernetes, large adoption en production
- Restore granulaire (cluster / namespace / ressource) satisfait tous les critères d'acceptation
- Workload Identity supporté — aucune credentials en clair dans le cluster
- DR vers un autre cluster documentable et testable
- Coût inférieur aux alternatives enterprise ou managées

### Négatives / Points de vigilance

- Un DaemonSet `node-agent` tourne sur chaque nœud (consommation mémoire ~100 Mi par nœud)
- Nécessite que l'OIDC Issuer soit activé sur l'AKS (changement dans `modules/aks/cluster.tf`)
- Le backup des volumes via kopia est un processus de copie des fichiers — il n'est pas crash-consistent pour PostgreSQL sans hook de quiesce. **Mitigation** : PostgreSQL dispose de sa propre réplication (3 replicas streaming) ; en cas de DR, la restauration depuis le backup Velero est complétée par un `pg_basebackup` si nécessaire. Les hooks Velero (pre/post) peuvent être configurés ultérieurement pour un snapshot applicatif-consistent.

---

## Références

- [Velero Documentation](https://velero.io/docs/)
- [velero-plugin-for-microsoft-azure](https://github.com/vmware-tanzu/velero-plugin-for-microsoft-azure)
- [Velero Workload Identity Azure](https://velero.io/docs/main/azure-config/)
- [ADR-003 — Workload Identity](ADR-003-workload-identity.md)