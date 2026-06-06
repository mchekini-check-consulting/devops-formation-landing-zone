# Plan de Déploiement — US Backup Velero

**User Story :** En tant que SRE, je veux que l'état du cluster (manifests + volumes) soit sauvegardé quotidiennement afin de pouvoir restaurer le cluster ou un namespace en cas de désastre.

| Champ          | Valeur                        |
|----------------|-------------------------------|
| Sprint         | Phase 04                      |
| Domaine        | SRE / Disaster Recovery       |
| Branche        | `feat/valero`                 |
| Auteur         | elGiordano                    |
| Statut         | **Déployé** (2026-06-05)      |

---

## Architecture déployée

```
AKS Cluster
└── namespace: velero
    ├── Deployment: velero-server            (velero v1.15.0 / chart 8.1.0)
    ├── DaemonSet:  node-agent               (kopia, toléré sur workload=database)
    ├── ServiceAccount: velero-server
    │   ├── annotation: azure.workload.identity/client-id = <UAMI-client-id>
    │   └── label: azure.workload.identity/use = "true"
    └── VolumeSnapshotClass: csi-azure-vsc
        ├── driver: disk.csi.azure.com
        └── label: velero.io/csi-volumesnapshot-class = "true"

Azure (rg-formation-ecom-aks)
├── Storage Account: stveleroformation
│   └── Blob Container: velero-backups  (Cool tier via lifecycle policy)
└── UAMI: uami-velero-formation
    ├── Role: Storage Blob Data Contributor → stveleroformation
    └── Federated Credential:
        issuer  = AKS OIDC Issuer URL
        subject = system:serviceaccount:velero:velero-server

Azure (MC_rg-formation-ecom-aks_aks-ecom-formation_francecentral)
└── Managed Disk Snapshots (CSI) — créés automatiquement par disk.csi.azure.com
    ├── velero-*-postgres-data-postgres-0
    ├── velero-*-postgres-data-postgres-1
    └── velero-*-postgres-data-postgres-2
```

### Flux de backup

```
01:30 UTC → Schedule daily-dev → velero-server
                                      │
                                      ├─ Sérialise les manifests K8s (namespace dev)
                                      │   └─ Upload → Azure Blob Container velero-backups (UAMI token OIDC)
                                      │
                                      └─ CSI Snapshots des PVCs PostgreSQL (3 replicas)
                                          └─ disk.csi.azure.com → Azure Managed Disk Snapshot (incrémental)
                                              stockés dans MC_rg-formation-ecom-aks_...
```

---

## Prérequis (état au moment du déploiement)

| Prérequis                          | État         | Fichier                                      |
|------------------------------------|--------------|----------------------------------------------|
| AKS cluster opérationnel           | OK           | —                                            |
| OIDC Issuer activé sur AKS         | OK           | `modules/aks/cluster.tf`                     |
| Workload Identity webhook activé   | OK           | `modules/aks/cluster.tf`                     |
| Helm provider Terraform configuré  | OK           | `modules/platform/`                          |
| Storage Account Velero             | OK           | `modules/velero/storage.tf`                  |
| UAMI + Federated Credential        | OK           | `modules/velero/identity.tf`                 |
| VolumeSnapshotClass csi-azure-vsc  | OK           | `k8s/velero/volumesnapshotclass.yaml`        |

---

## Phase 1 — Prérequis AKS : OIDC + Workload Identity

**Fichier modifié :** `modules/aks/cluster.tf`

```hcl
resource "azurerm_kubernetes_cluster" "aks" {
  # ...
  oidc_issuer_enabled       = true
  workload_identity_enabled = true
}
```

**Fichier modifié :** `modules/aks/outputs.tf`

```hcl
output "oidc_issuer_url" {
  value = azurerm_kubernetes_cluster.aks.oidc_issuer_url
}
```

---

## Phase 2 — Infrastructure Azure (module `modules/velero`)

### `modules/velero/storage.tf`

```hcl
resource "azurerm_storage_account" "velero" {
  name                     = "stvelero${var.team_name}"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  blob_properties {
    delete_retention_policy { days = 7 }
  }
  tags = var.tags
}

resource "azurerm_storage_container" "velero" {
  name                  = "velero-backups"
  storage_account_name  = azurerm_storage_account.velero.name
  container_access_type = "private"
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
  name                = "fedcred-velero-${var.team_name}"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.velero.id

  issuer   = var.aks_oidc_issuer_url
  subject  = "system:serviceaccount:velero:velero-server"  # nom exact du SA dans le chart 8.x
  audience = ["api://AzureADTokenExchange"]
}
```

> **Point critique :** Le chart Velero 8.x crée un ServiceAccount nommé `velero-server`. Les versions antérieures utilisaient `velero`. Un `subject` incorrect provoque une erreur `AADSTS700213` lors de l'échange de token.

---

## Phase 3 — Installation Velero (Helm via Terraform)

**Fichier :** `modules/platform/velero.tf`

```hcl
resource "helm_release" "velero" {
  name             = "velero"
  repository       = "https://vmware-tanzu.github.io/helm-charts"
  chart            = "velero"
  version          = "8.1.0"
  namespace        = "velero"
  create_namespace = true

  values = [
    templatefile("${path.root}/k8s/velero/velero-values.yaml", {
      storage_account   = var.velero_storage_account
      storage_container = var.velero_storage_container
      resource_group    = var.velero_resource_group
      subscription_id   = var.velero_subscription_id
      uami_client_id    = var.velero_uami_client_id
    })
  ]
}
```

**Fichier :** `k8s/velero/velero-values.yaml`

```yaml
image:
  repository: velero/velero
  tag: v1.15.0

upgradeCRDs: false   # évite le hook bitnami/kubectl incompatible avec le registry

initContainers:
  - name: velero-plugin-for-azure
    image: velero/velero-plugin-for-microsoft-azure:v1.11.0
    imagePullPolicy: IfNotPresent
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
  features: EnableCSI   # active les CSI Volume Snapshots (doit être sous configuration:, pas à la racine)

  backupStorageLocation:
    - name: default
      provider: azure
      bucket: ${storage_container}
      config:
        resourceGroup: ${resource_group}
        storageAccount: ${storage_account}
        subscriptionId: ${subscription_id}
        storageAccountKeyEnvVar: ""   # désactive la recherche de clé SA
        useAAD: "true"                # utilise le token Workload Identity (nécessaire pour éviter AuthorizationFailed)

  volumeSnapshotLocation:
    - name: default
      provider: azure
      config:
        resourceGroup: ${resource_group}
        subscriptionId: ${subscription_id}
        # pas de useAAD ici — non supporté en v1.11.0, les snapshots PVC passent par CSI

credentials:
  useSecret: false   # pas de Secret K8s — authentification via Workload Identity

nodeAgent:
  podVolumePath: /var/lib/kubelet/pods
  privileged: false
  tolerations:
    - key: "workload"
      operator: "Equal"
      value: "database"
      effect: "NoSchedule"

schedules:
  daily-dev:
    disabled: false
    schedule: "30 1 * * *"   # 01:30 UTC chaque nuit
    useOwnerReferencesInBackup: false
    template:
      ttl: "168h"             # rétention 7 jours
      includedNamespaces:
        - "dev"
      includeClusterResources: false
      snapshotVolumes: true   # active les CSI snapshots des PVCs
```

---

## Phase 4 — VolumeSnapshotClass (hors Terraform)

La `VolumeSnapshotClass` est appliquée directement avec `kubectl` car elle est une ressource cluster-level qui précède l'installation de Velero :

```bash
kubectl apply -f k8s/velero/volumesnapshotclass.yaml
```

**Fichier :** `k8s/velero/volumesnapshotclass.yaml`

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

> **À rejouer si le cluster est recréé** — cette ressource n'est pas gérée par Terraform.

---

## Erreurs rencontrées et solutions

| Erreur | Cause | Solution |
|--------|-------|----------|
| `412 There is currently a lease on the blob` | Terraform state lock non libéré | `az storage blob lease break --account-name sanecomformation --container-name ecom-formation-tfstate --blob-name terraform.tfstate --auth-mode login` |
| `velero has no deployed releases` | Helm release en état failed | `helm uninstall velero -n velero` + `terraform state rm module.platform.helm_release.velero` |
| `AADSTS700213` — wrong token subject | `subject` du federated credential pointait vers `velero` au lieu de `velero-server` | Corriger `subject = "system:serviceaccount:velero:velero-server"` dans `identity.tf` |
| `AuthorizationFailed` sur `listKeys` | `useAAD: "true"` manquant dans la config BSL | Ajouter `useAAD: "true"` dans la config du BSL |
| `config has invalid keys [useAAD]` | `useAAD` est invalide dans la config VSL en v1.11.0 | Supprimer `useAAD` du VSL — utiliser CSI snapshots à la place |
| `AZURE_SUBSCRIPTION_ID is required` | VSL cherche un fichier credentials — incompatible avec Workload Identity | Utiliser CSI Volume Snapshots (`configuration.features: EnableCSI`) |
| `features: EnableCSI` sans effet | La clé était à la racine du YAML au lieu de sous `configuration:` | Déplacer sous `configuration:` |
| Hook `bitnami/kubectl:1.33` introuvable | CRD upgrade hook utilise une image indisponible | Ajouter `upgradeCRDs: false` |

---

## Critères de validation (DoD)

| Critère                                             | Validation                                                     |
|-----------------------------------------------------|----------------------------------------------------------------|
| Velero installé via Helm chart officiel             | `helm list -n velero` → `velero 8.1.0` DEPLOYED               |
| BSL disponible (Workload Identity fonctionnel)      | `velero backup-location get` → Status: Available               |
| Schedule daily-dev actif                            | `velero schedule get daily-dev` → schedule 30 1 * * *         |
| CSI VolumeSnapshotClass présente et labellisée      | `kubectl get volumesnapshotclass csi-azure-vsc`                |
| Backup manuel avec snapshots CSI                    | `kubectl get volumesnapshotcontent` → READYTOUSE: true (×3)    |
| Workload Identity — pas de Secret avec clé Azure    | `kubectl get secret -n velero` → aucun secret cloud           |
| Restore namespace documenté                         | `docs/explications/velero/velero-restore.md`                   |

---

## Liens vers les ADRs

| ADR | Décision |
|-----|----------|
| [ADR-001](../../adr/velero/ADR-001-velero-backup-solution.md) | Choix de Velero comme solution de backup Kubernetes |
| [ADR-002](../../adr/velero/ADR-002-azure-blob-storage-cool-tier.md) | Azure Blob Storage Standard LRS Cool tier |
| [ADR-003](../../adr/velero/ADR-003-workload-identity.md) | Workload Identity pour l'authentification Velero |
| [ADR-004](../../adr/velero/ADR-004-helm-chart-officiel.md) | Helm chart officiel VMware Tanzu |
| [ADR-005](../../adr/velero/ADR-005-backup-schedule-strategy.md) | Stratégie de schedule |
| [ADR-006](../../adr/velero/ADR-006-retention-policy.md) | Politique de rétention 7j |
| [ADR-007](../../adr/velero/ADR-007-csi-volume-snapshots.md) | CSI Volume Snapshots pour les PVCs PostgreSQL |