# ADR-004 — Helm chart officiel VMware Tanzu pour l'installation de Velero

| Champ      | Valeur                  |
|------------|-------------------------|
| Statut     | Accepté                 |
| Date       | 2026-05-30              |
| Auteur     | elGiordano              |
| Contexte   | Phase 04 — US Backup DR |

---

## Contexte

Velero doit être installé dans le cluster AKS. Plusieurs mécanismes d'installation sont disponibles. Le projet utilise déjà Terraform avec le provider Helm pour gérer les composants de la couche platform (cf. `modules/platform/ingress.tf` — NGINX Ingress Controller installé via `helm_release`).

La question est : **quel mécanisme d'installation choisir pour Velero ?**

---

## Décision

Utiliser le **Helm chart officiel VMware Tanzu** (`velero/velero`) déployé via une ressource Terraform `helm_release` dans le module `modules/platform/`, en suivant le même pattern que NGINX Ingress.

```hcl
resource "helm_release" "velero" {
  name       = "velero"
  repository = "https://vmware-tanzu.github.io/helm-charts"
  chart      = "velero"
  version    = "8.1.0"      # version pinned
  namespace  = "velero"
  create_namespace = true
  values = [templatefile("${path.module}/velero-values.yaml", { ... })]
}
```

---

## Alternatives considérées

### Option A — CLI `velero install` (binaire officiel)

```bash
velero install \
  --provider azure \
  --plugins velero/velero-plugin-for-microsoft-azure:v1.11.0 \
  --bucket velero-backups \
  --use-node-agent
```

- **Avantages :** Simple, rapide pour un test rapide
- **Problèmes :**
  - Impératif, non déclaratif — pas de réconciliation d'état (si quelqu'un modifie un manifest manuellement, Terraform ne le détecte pas)
  - Pas versionnable facilement dans le state Terraform
  - Incompatible avec la philosophie IaC du projet (tout est Terraform)
  - Nécessite la CLI `velero` dans le pipeline CI/CD
- **Décision : rejeté** — brise la cohérence IaC

### Option B — Manifests YAML statiques (kubectl apply)

```bash
kubectl apply -f https://github.com/vmware-tanzu/velero/releases/download/v1.15.0/velero-v1.15.0-linux-amd64.tar.gz
```

- **Avantages :** Contrôle total sur chaque ressource
- **Problèmes :**
  - Fragiles : à chaque nouvelle version de Velero, les manifests upstream changent et la divergence est invisible
  - Gestion manuelle des CRDs (CustomResourceDefinitions) — ordre d'application critique
  - Aucune abstraction sur la configuration : chaque paramètre doit être patché manuellement
  - Incompatible avec `helm diff` pour les revues de changement
  - Le projet n'utilise pas `kubectl apply` directement dans son infrastructure (tout est Helm via Terraform)
- **Décision : rejeté** — fragilité opérationnelle

### Option C — Kustomize

```yaml
# kustomization.yaml
resources:
  - https://github.com/vmware-tanzu/velero//config/crd
patches:
  - ...
```

- **Avantages :** Déclaratif, compatible GitOps, gestion des overlays (dev/prod)
- **Problèmes :**
  - Non intégré dans le workflow Terraform actuel du projet
  - Nécessite un outil supplémentaire dans le pipeline (kubectl kustomize ou flux)
  - Pas de gestion native des chart versions avec SemVer
  - Le projet n'a pas de structure d'overlays Kustomize — ajout d'une nouvelle couche de complexité
- **Décision : rejeté** — rupture de cohérence technologique, complexité non justifiée

### Option D — Helm chart officiel via Terraform ✅ (choisie)

- **Cohérence :** même pattern que `helm_release.nginx_ingress` dans `modules/platform/ingress.tf`
- **Déclaratif :** `terraform apply` réconcilie l'état désiré (chart + values) avec l'état réel
- **Versioning explicite :** `version = "8.1.0"` — upgrades contrôlés via PR + `terraform plan`
- **Valeurs typées :** `templatefile()` permet d'injecter les outputs Terraform (UAMI client ID, Storage Account name) dans les values Velero sans manipulation manuelle
- **Rollback :** `terraform apply` avec une version précédente suffit
- **Historique :** git blame sur `velero-values.yaml` donne l'historique de chaque changement de configuration
- **Plugin géré** : le init-container `velero-plugin-for-microsoft-azure` est déclaré dans les values — pas d'étape manuelle

### Option E — ArgoCD / Flux (GitOps)

- **Avantages :** Réconciliation continue, drift detection, interface graphique
- **Problèmes :**
  - ArgoCD ou Flux ne sont pas dans le scope du projet actuel
  - Ajouter un opérateur GitOps pour installer Velero seul est disproportionné
  - Complexité d'initialisation (chicken-and-egg : qui installe l'opérateur ?)
- **Décision : rejeté** — hors scope, complexité injustifiée

---

## Détails du chart

| Paramètre           | Valeur                                                      |
|---------------------|-------------------------------------------------------------|
| Repository          | `https://vmware-tanzu.github.io/helm-charts`               |
| Chart               | `velero`                                                    |
| Version             | `8.1.0` (Velero server `v1.15.0`)                           |
| Plugin Azure        | `velero/velero-plugin-for-microsoft-azure:v1.11.0`          |
| Namespace           | `velero` (créé par Helm si absent)                          |
| Config extérieure   | `velero-values.yaml` via `templatefile()`                   |
| Schedules           | Déclarés dans `values.yaml` section `schedules:`            |

### Pourquoi pinner la version ?

Le chart Velero évolue avec des breaking changes entre versions majeures (ex : v5→v6 modifie la structure des BackupStorageLocations). Une version non pinnée (`chart = "velero"` sans `version`) prendrait la dernière version au prochain `terraform init -upgrade`, risquant de casser l'installation sans changement intentionnel dans le code. Le pinning garantit que les upgrades sont **explicites et revus**.

---

## Conséquences

### Positives

- Zéro nouvelle technologie introduite — le provider Helm est déjà configuré
- Plan Terraform complet avant chaque changement (`helm diff` intégré via `terraform plan`)
- Les schedules de backup sont versionés dans git avec le reste de l'infrastructure
- Les secrets (UAMI client ID, Storage Account name) sont injectés proprement via templatefile, pas hardcodés

### Négatives / Points de vigilance

- `velero-values.yaml` contient du HCL (`templatefile`) — il ne peut pas être testé avec `helm template` seul sans les variables Terraform
- Les upgrades de version du chart nécessitent une vérification du changelog Velero pour les breaking changes
- La taille du chart (CRDs inclus) peut allonger légèrement le `terraform apply` (~2–3 minutes)

---

## Références

- [Helm chart Velero officiel](https://github.com/vmware-tanzu/helm-charts/tree/main/charts/velero)
- [Velero plugin for Microsoft Azure](https://github.com/vmware-tanzu/velero-plugin-for-microsoft-azure)
- [Terraform helm_release resource](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release)
- [ADR-001 — Choix de Velero](ADR-001-velero-backup-solution.md)