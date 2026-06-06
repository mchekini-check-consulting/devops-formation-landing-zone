# ADR-003 — Workload Identity pour l'authentification Velero vers Azure

| Champ      | Valeur                  |
|------------|-------------------------|
| Statut     | Accepté                 |
| Date       | 2026-05-30              |
| Auteur     | elGiordano              |
| Contexte   | Phase 04 — US Backup DR |

---

## Contexte

Velero doit écrire et lire des données dans Azure Blob Storage. Cela nécessite une authentification auprès de l'API Azure. Il existe plusieurs mécanismes d'authentification pour un workload tournant dans AKS.

Le critère d'acceptation explicite de la User Story stipule : **"Workload Identity Velero pour accès au Blob Storage (pas de credentials en clair)"**.

Par ailleurs, le cluster AKS actuel utilise `identity { type = "SystemAssigned" }` mais n'a pas encore l'OIDC Issuer activé — prérequis du Workload Identity.

---

## Décision

Utiliser **Azure Workload Identity** avec un **User Assigned Managed Identity (UAMI)** et un **Federated Identity Credential** lié à l'OIDC Issuer de l'AKS.

### Mécanisme technique

```
1. AKS OIDC Issuer expose un endpoint JWT (oidc_issuer_url)
2. Le ServiceAccount K8s "velero-server" dans le namespace "velero"
   porte l'annotation azure.workload.identity/client-id = <UAMI-client-id>
3. Au démarrage du pod velero-server, le webhook azure-workload-identity
   monte automatiquement un token OIDC projeté dans /var/run/secrets/azure/tokens/
4. Le SDK Azure dans velero-plugin-for-azure échange ce token OIDC
   contre un access token Azure AD via le Federated Credential
5. L'access token est utilisé pour appeler l'API Blob Storage
   (rôle Storage Blob Data Contributor limité au Storage Account Velero)
```

### Ressources Terraform créées

```hcl
# modules/velero/identity.tf
azurerm_user_assigned_identity      "velero"      # UAMI dédié
azurerm_role_assignment             "velero_blob" # RBAC scopé au SA
azurerm_federated_identity_credential "velero"    # Lien OIDC ↔ UAMI

# modules/aks/cluster.tf (modification)
oidc_issuer_enabled       = true  # expose le JWKS endpoint
workload_identity_enabled = true  # installe le webhook mutating
```

---

## Alternatives considérées

### Option A — Service Principal + Secret dans Kubernetes Secret

```yaml
# Ce qu'on évite :
apiVersion: v1
kind: Secret
metadata:
  name: velero-azure-credentials
data:
  cloud: base64(AZURE_CLIENT_SECRET=xxx)
```

- **Problèmes :**
  - Credentials statiques stockés dans etcd (dans le cluster) — exposés si etcd est compromis
  - Rotation manuelle : oubli = credential expiré en production = backup en échec silencieux
  - Secrets Kubernetes non chiffrés par défaut dans etcd sur AKS (sans Azure Disk Encryption for etcd activé)
  - Crédit Azure AD bloqué si le secret est détecté par Microsoft Defender for Cloud
- **Décision : rejeté** — violé le critère d'acceptation "pas de credentials en clair"

### Option B — Storage Account Key dans un Kubernetes Secret

```hcl
# Ce qu'on évite :
AZURE_STORAGE_KEY = "abc123..."
```

- **Problèmes :**
  - La Storage Account Key donne un accès **total** au compte (pas de RBAC granulaire)
  - Impossible de restreindre à un seul container via une clé
  - Rotation manuelle (2 clés disponibles, mais processus opérationnel risqué)
  - SAS Token comme alternative partielle mais gestion de l'expiration complexe
- **Décision : rejeté** — surface d'attaque trop large, credentials statiques

### Option C — Azure Pod Identity v1 (aad-pod-identity)

- Première génération de l'identité managée pour pods AKS
- **Problèmes :**
  - **Deprecated** depuis 2022 — Microsoft a officiellement arrêté le développement
  - End-of-life : pas de support sécurité au-delà de 2025
  - Remplacé officiellement par Azure Workload Identity
- **Décision : rejeté** — end-of-life

### Option D — SystemAssigned MSI du node pool

- Utiliser l'identité managée des nœuds AKS (déjà `SystemAssigned` sur le cluster)
- Assigner le rôle Blob Contributor à l'identité de l'agent pool
- **Problèmes :**
  - L'identité du nœud est **partagée** par tous les pods sur ce nœud
  - Un pod compromis peut accéder au Blob Storage Velero sans être Velero
  - Violation du principe du **moindre privilège** (least privilege)
  - Impossible de distinguer quel pod a effectué quelle action dans les logs Azure
- **Décision : rejeté** — principe de moindre privilège violé

### Option E — Azure Workload Identity (UAMI + Federated Credential) ✅ (choisie)

- Aucune credentials stockées — le token est dynamique, de courte durée (~1h), renouvelé automatiquement
- RBAC scopé : rôle `Storage Blob Data Contributor` uniquement sur le Storage Account Velero
- Auditabilité : chaque opération sur le Blob Storage est tracée avec l'identité UAMI dans Azure Activity Log
- Support officiel Microsoft depuis AKS 1.24+
- Supporté nativement par `velero-plugin-for-microsoft-azure` depuis v1.8.0

---

## Prérequis et impact sur le cluster existant

L'activation du Workload Identity nécessite deux modifications dans `modules/aks/cluster.tf` :

```hcl
resource "azurerm_kubernetes_cluster" "aks" {
  # ... existant ...
  oidc_issuer_enabled       = true  # NOUVEAU
  workload_identity_enabled = true  # NOUVEAU
}
```

**Impact :** `terraform apply` effectue une modification **in-place** sur l'AKS (pas de re-création). Microsoft confirme que cette opération est non-disruptive pour les workloads existants — le webhook mutating est ajouté à l'API server sans redémarrage des nœuds.

**Validation post-apply :**
```bash
az aks show -g <rg> -n <aks> --query oidcIssuerProfile
# Expected: { "enabled": true, "issuerUrl": "https://..." }
```

---

## Configuration Kubernetes côté Velero

### ServiceAccount et annotations

Le ServiceAccount Velero doit porter l'annotation et le label requis par le webhook.

> **Important :** Le chart Helm Velero 8.x crée le ServiceAccount sous le nom **`velero-server`** (pas `velero`). Le `subject` du Federated Credential doit correspondre exactement — une erreur `AADSTS700213` indique un `subject` incorrect.

```hcl
# modules/velero/identity.tf — Federated Credential
resource "azurerm_federated_identity_credential" "velero" {
  subject  = "system:serviceaccount:velero:velero-server"  # nom exact du SA créé par le chart 8.x
  audience = ["api://AzureADTokenExchange"]
}
```

```yaml
# k8s/velero/velero-values.yaml — Helm values
podLabels:
  azure.workload.identity/use: "true"

serviceAccount:
  server:
    annotations:
      azure.workload.identity/client-id: "${uami_client_id}"
```

### Configuration BSL avec `useAAD: "true"`

Pour que le plugin Azure utilise le token Workload Identity au lieu de chercher une clé de Storage Account (`listKeys`), il faut explicitement activer l'AAD dans la config BSL :

```yaml
configuration:
  backupStorageLocation:
    - name: default
      provider: azure
      config:
        storageAccountKeyEnvVar: ""   # désactive la recherche de clé
        useAAD: "true"                # active l'authentification via token OIDC
```

Sans `useAAD: "true"`, le plugin tente d'appeler `listKeys` sur le Storage Account — ce qui échoue avec `AuthorizationFailed` car le rôle `Storage Blob Data Contributor` n'accorde pas cette permission (opération de management plane).

### Note sur le VSL et Workload Identity

Le plugin `velero-plugin-for-microsoft-azure` v1.11.0 **ne supporte pas** `useAAD` pour le `VolumeSnapshotLocation` (VSL) :

```yaml
# INVALIDE en v1.11.0 — ne pas faire :
volumeSnapshotLocation:
  config:
    useAAD: "true"  # → "config has invalid keys [useAAD]"
```

La sauvegarde des PVCs est donc gérée via **CSI Volume Snapshots** (`disk.csi.azure.com`) qui n'a pas besoin de VSL credentials — voir [ADR-007](ADR-007-csi-volume-snapshots.md).

---

## Conséquences

### Positives

- Zero-credentials dans le cluster — conforme au critère d'acceptation
- Tokens de courte durée (1h) avec renouvellement automatique — aucune maintenance
- RBAC précis : `Storage Blob Data Contributor` sur le périmètre Velero uniquement
- Logs d'audit complets dans Azure Monitor : qui a accédé au blob, quand, depuis quel pod
- Pattern réutilisable pour d'autres workloads nécessitant un accès Azure (ex: application accédant à Key Vault)

### Négatives / Points de vigilance

- Ajoute une ressource Terraform supplémentaire (`azurerm_federated_identity_credential`)
- L'OIDC Issuer URL doit être propagée depuis le module AKS vers le module Velero (output → variable)
- Si le namespace ou le nom du ServiceAccount change, le `subject` du Federated Credential doit être mis à jour manuellement
- Le chart Velero 8.x utilise `velero-server` comme nom de SA — différent de `velero` utilisé dans les versions antérieures

---

## Références

- [Azure Workload Identity for AKS](https://learn.microsoft.com/fr-fr/azure/aks/workload-identity-overview)
- [Velero Azure Workload Identity configuration](https://velero.io/docs/main/azure-config/#option-1-use-azure-workload-identity)
- [azurerm_federated_identity_credential](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/federated_identity_credential)
- [ADR-001 — Choix de Velero](ADR-001-velero-backup-solution.md)
- [ADR-007 — CSI Volume Snapshots](ADR-007-csi-volume-snapshots.md)