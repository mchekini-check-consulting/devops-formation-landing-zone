# Plan de Déploiement — US Backup Velero

**User Story :** En tant que SRE, je veux que l'état du cluster (manifests + volumes) soit sauvegardé quotidiennement afin de pouvoir restaurer le cluster ou un namespace en cas de désastre.

| Champ          | Valeur                        |
|----------------|-------------------------------|
| Sprint         | Phase 04                      |
| Domaine        | SRE / Disaster Recovery       |
| Durée estimée  | 2–3 jours                     |
| Branche        | `feat/velero-backup`          |
| Auteur         | elGiordano                    |

---

## Architecture cible

```
AKS Cluster
└── namespace: velero
    ├── Deployment: velero-server
    ├── DaemonSet:  node-agent (backup volumes avec kopia)
    └── ServiceAccount: velero
        └── annotation: azure.workload.identity/client-id = <UAMI-client-id>

Azure (rg-platform-formation)
├── Storage Account: stvelerformation
│   └── Blob Container: velero-backups  (Cool tier via lifecycle policy)
└── UAMI: uami-velero-formation
    ├── Role: Storage Blob Data Contributor  → Storage Account
    └── Federated Credential: AKS OIDC Issuer → system:serviceaccount:velero:velero
```

### Flux de backup

```
01:00 UTC → Schedule daily-full-cluster → velero-server
                                              │
                                              ├─ Sérialise tous les manifests K8s
                                              ├─ Déclenche kopia sur node-agent (PVs)
                                              └─ Upload → Azure Blob (Cool) via UAMI (token OIDC)

01:30 UTC → Schedules daily-<namespace> (même flux, scope namespace)
```

---

## Prérequis

| Prérequis                          | État actuel       | Action requise                          |
|------------------------------------|-------------------|-----------------------------------------|
| AKS cluster opérationnel           | OK                | —                                       |
| OIDC Issuer activé sur AKS         | **MANQUANT**      | Ajouter `oidc_issuer_enabled = true` dans `modules/aks/cluster.tf` |
| Workload Identity webhook activé   | **MANQUANT**      | Ajouter `workload_identity_enabled = true` dans `modules/aks/cluster.tf` |
| Helm provider Terraform configuré  | OK (platform)     | Réutiliser le même provider             |
| kubectl accès au cluster           | OK                | —                                       |
| Terraform state dans Azure Storage | OK                | —                                       |

---

## Phase 1 — Prérequis AKS : OIDC + Workload Identity

**Fichier modifié :** `modules/aks/cluster.tf`

Ajouter dans `azurerm_kubernetes_cluster` :

```hcl
oidc_issuer_enabled       = true
workload_identity_enabled = true
```

**Fichier modifié :** `modules/aks/outputs.tf`

Ajouter :

```hcl
output "oidc_issuer_url" {
  value = azurerm_kubernetes_cluster.aks.oidc_issuer_url
}
```

**Impact :** Redéploiement de l'AKS (plan Terraform sans downtime — modification in-place).

---

## Phase 2 — Infrastructure Azure (nouveau module `modules/velero`)

Créer le répertoire `modules/velero/` avec les fichiers suivants.

### `modules/velero/storage.tf`

```hcl
resource "azurerm_storage_account" "velero" {
  name                     = "stvelero${var.team_name}"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  access_tier              = "Cool"

  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }

  tags = var.tags
}

resource "azurerm_storage_container" "velero" {
  name                  = "velero-backups"
  storage_account_name  = azurerm_storage_account.velero.name
  container_access_type = "private"
}

# Lifecycle : bascule en Archive après 30j, suppression après 45j
resource "azurerm_storage_management_policy" "velero" {
  storage_account_id = azurerm_storage_account.velero.id

  rule {
    name    = "velero-lifecycle"
    enabled = true

    filters {
      blob_types   = ["blockBlob"]
      prefix_match = ["velero-backups/"]
    }

    actions {
      base_blob {
        tier_to_archive_after_days_since_modification_greater_than = 30
        delete_after_days_since_modification_greater_than          = 45
      }
    }
  }
}
```

### `modules/velero/identity.tf`

```hcl
resource "azurerm_user_assigned_identity" "velero" {
  name                = "uami-velero-${var.team_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_role_assignment" "velero_blob" {
  scope                = azurerm_storage_account.velero.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.velero.principal_id
}

resource "azurerm_federated_identity_credential" "velero" {
  name                = "fedcred-velero"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.velero.id

  issuer   = var.aks_oidc_issuer_url
  subject  = "system:serviceaccount:velero:velero"
  audience = ["api://AzureADTokenExchange"]
}
```

### `modules/velero/outputs.tf`

```hcl
output "storage_account_name"    { value = azurerm_storage_account.velero.name }
output "storage_container_name"  { value = azurerm_storage_container.velero.name }
output "uami_client_id"          { value = azurerm_user_assigned_identity.velero.client_id }
output "resource_group_name"     { value = var.resource_group_name }
```

### `modules/velero/variables.tf`

```hcl
variable "team_name"          { type = string }
variable "location"           { type = string }
variable "resource_group_name"{ type = string }
variable "aks_oidc_issuer_url"{ type = string }
variable "tags"               { type = map(string); default = {} }
```

### Appel dans `main.tf` (racine)

```hcl
module "velero" {
  source              = "./modules/velero"
  team_name           = var.team_name
  location            = var.location
  resource_group_name = module.hub.resource_group_name
  aks_oidc_issuer_url = module.aks.oidc_issuer_url
  tags                = local.common_tags
}
```

---

## Phase 3 — Installation Velero (Helm via Terraform)

**Fichier créé :** `modules/platform/velero.tf`

```hcl
resource "helm_release" "velero" {
  name             = "velero"
  repository       = "https://vmware-tanzu.github.io/helm-charts"
  chart            = "velero"
  version          = "8.1.0"
  namespace        = "velero"
  create_namespace = true

  values = [
    templatefile("${path.module}/velero-values.yaml", {
      storage_account   = var.velero_storage_account
      storage_container = var.velero_storage_container
      resource_group    = var.velero_resource_group
      subscription_id   = var.subscription_id
      uami_client_id    = var.velero_uami_client_id
    })
  ]
}
```

**Fichier créé :** `modules/platform/velero-values.yaml`

```yaml
image:
  repository: velero/velero
  tag: v1.15.0

initContainers:
  - name: velero-plugin-for-azure
    image: velero/velero-plugin-for-microsoft-azure:v1.11.0
    volumeMounts:
      - mountPath: /target
        name: plugins

podLabels:
  azure.workload.identity/use: "true"

serviceAccount:
  server:
    annotations:
      azure.workload.identity/client-id: "${uami_client_id}"

configuration:
  backupStorageLocation:
    - name: default
      provider: azure
      bucket: ${storage_container}
      config:
        resourceGroup: ${resource_group}
        storageAccount: ${storage_account}
        subscriptionId: ${subscription_id}
        storageAccountKeyEnvVar: ""

  volumeSnapshotLocation:
    - name: default
      provider: azure
      config:
        resourceGroup: ${resource_group}
        subscriptionId: ${subscription_id}

credentials:
  useSecret: false

nodeAgent:
  podVolumePath: /var/lib/kubelet/pods
  privileged: false
  tolerations:
    - key: "workload"
      operator: "Equal"
      value: "database"
      effect: "NoSchedule"

schedules:
  daily-full-cluster:
    disabled: false
    schedule: "0 1 * * *"
    template:
      ttl: "336h"
      includedNamespaces:
        - "*"
      includeClusterResources: true
      snapshotVolumes: true

  daily-dev:
    disabled: false
    schedule: "30 1 * * *"
    template:
      ttl: "168h"
      includedNamespaces:
        - "dev"
      includeClusterResources: false
      snapshotVolumes: true

  daily-ingress-nginx:
    disabled: false
    schedule: "45 1 * * *"
    template:
      ttl: "168h"
      includedNamespaces:
        - "ingress-nginx"
      includeClusterResources: false
      snapshotVolumes: false
```

**Variables à ajouter** dans `modules/platform/variables.tf` :

```hcl
variable "velero_storage_account"  { type = string }
variable "velero_storage_container"{ type = string }
variable "velero_resource_group"   { type = string }
variable "velero_uami_client_id"   { type = string }
variable "subscription_id"         { type = string }
```

---

## Phase 4 — Documentation

Créer `docs/velero-restore.md` (voir fichier dédié).

---

## Plan d'exécution

```
Jour 1 (matin)
  ├── PR : ajout OIDC/Workload Identity dans modules/aks/cluster.tf
  ├── terraform plan → vérifier impact (in-place, no downtime)
  └── terraform apply → AKS mis à jour

Jour 1 (après-midi)
  ├── PR : module modules/velero/ (storage + identity)
  ├── terraform plan → valider ressources Azure créées
  └── terraform apply → Storage Account + UAMI + Federated Credential

Jour 2 (matin)
  ├── PR : modules/platform/velero.tf + velero-values.yaml
  ├── terraform plan → Helm release Velero
  └── terraform apply → Velero installé dans namespace velero

Jour 2 (après-midi)
  ├── Validation : velero backup create test-manual --wait
  ├── kubectl get backups -n velero
  ├── Vérifier blobs dans Azure Storage
  └── Test restore namespace dev (voir docs/velero-restore.md)

Jour 3
  ├── Attendre le premier backup schedulé (01:00 UTC)
  ├── Valider complétude du backup daily-full-cluster
  ├── Rédiger docs/velero-restore.md
  └── Merge + tag de release
```

---

## Critères de validation (DoD)

| Critère                                             | Validation                                                    |
|-----------------------------------------------------|---------------------------------------------------------------|
| Velero installé via Helm chart officiel             | `helm list -n velero` affiche `velero 8.1.0`                 |
| Backend Azure Blob Standard LRS Cool tier           | Visible dans le portail Azure                                 |
| Schedule daily-full-cluster à 01:00 UTC, 14j        | `velero schedule get daily-full-cluster`                     |
| Schedule daily-\<namespace\> par namespace, 7j       | `velero schedule get daily-dev`                              |
| Workload Identity (pas de credentials en clair)     | Aucun Secret K8s avec clé Azure dans namespace velero        |
| Restore namespace documenté                         | `docs/velero-restore.md` mergé dans main                     |
| Restore ressource spécifique documenté              | idem                                                          |
| Restore DR documenté                                | idem                                                          |

---

## Liens vers les ADRs

| ADR | Décision |
|-----|----------|
| [ADR-001](../../adr/velero/ADR-001-velero-backup-solution.md)       | Choix de Velero comme solution de backup Kubernetes |
| [ADR-002](../../adr/velero/ADR-002-azure-blob-storage-cool-tier.md) | Azure Blob Storage Standard LRS Cool tier           |
| [ADR-003](../../adr/velero/ADR-003-workload-identity.md)            | Workload Identity pour l'authentification Velero    |
| [ADR-004](../../adr/velero/ADR-004-helm-chart-officiel.md)          | Helm chart officiel VMware Tanzu                    |
| [ADR-005](../../adr/velero/ADR-005-backup-schedule-strategy.md)     | Stratégie de schedule double niveau                 |
| [ADR-006](../../adr/velero/ADR-006-retention-policy.md)             | Politique de rétention 14j / 7j                    |