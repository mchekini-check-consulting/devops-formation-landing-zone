# Module Spoke

Module Terraform pour créer un **Spoke** dans l'architecture Hub & Spoke.

Un Spoke représente un **projet** avec plusieurs **environnements** (dev, qua, prod).

## 📋 Vue d'ensemble

Ce module crée pour chaque environnement :
- ✅ 1 Resource Group
- ✅ 1 VNet
- ✅ 3 Subnets (frontend, backend, data)
- ✅ 3 Network Security Groups avec règles
- ✅ 2 VNet Peerings (Hub ↔ Spoke)
- ✅ Des NICs privées pour les VMs front/back des environnements ciblés
- ✅ Des VMs Linux Ubuntu avec Docker installé via cloud-init
- ✅ 1 Managed Identity avec rôle AcrPull sur l'ACR du Hub

## 🏗️ Architecture

```
Spoke "ecom" avec 3 environnements
│
├── Dev (10.1.0.0/16)
│   ├── rg-formation-ecom-dev
│   ├── vnet-formation-ecom-dev
│   ├── subnet-front-dev (10.1.0.0/24) + NSG
│   │   └── vm-formation-ecom-front-dev-01 + NIC privée
│   ├── subnet-back-dev (10.1.1.0/24) + NSG
│   │   └── vm-formation-ecom-back-dev-01 + NIC privée
│   └── subnet-data-dev (10.1.2.0/24) + NSG
│
├── Qua (10.2.0.0/16)
│   └── [même structure]
│
└── Prod (10.3.0.0/16)
    └── [même structure]
```

## 📁 Structure du Module

```
modules/spoke/
├── main.tf         # Resource Groups + VNets + Subnets
├── nsg.tf          # Network Security Groups et règles
├── peering.tf      # VNet Peering Hub ↔ Spoke
├── vm.tf           # NICs + VMs Linux + cloud-init Docker
├── acr-access.tf   # Managed Identity + Role Assignment AcrPull
├── variables.tf    # Variables d'entrée
├── outputs.tf      # Outputs
└── README.md       # Ce fichier
```

## 🔧 Utilisation

### Exemple Basique

```hcl
module "ecom" {
  source = "./modules/spoke"

  team_name               = "formation"
  project_name            = "ecom"
  location                = "francecentral"
  environments            = ["dev", "qua", "prod"]
  address_spaces          = {
    dev  = "10.1.0.0/16"
    qua  = "10.2.0.0/16"
    prod = "10.3.0.0/16"
  }
  hub_vnet_id             = module.hub.vnet_hub_id
  hub_vnet_name           = module.hub.vnet_hub_name
  hub_resource_group_name = module.hub.resource_group_name

  key_vault_id               = module.hub.key_vault_id
  ssh_public_key_secret_name = "vm-admin-ssh-public-key"

  vm_size           = "Standard_B2ts_v2"
  vm_count          = { front = 1, back = 1 }
  vm_environments   = ["dev"]
  vm_admin_username = "azureuser"
}
```

### Exemple avec Tags Personnalisés

```hcl
module "analytics" {
  source = "./modules/spoke"

  team_name               = "formation"
  project_name            = "analytics"
  location                = "francecentral"
  environments            = ["dev", "prod"]  # Uniquement 2 environnements
  address_spaces          = {
    dev  = "10.4.0.0/16"
    prod = "10.5.0.0/16"
  }
  hub_vnet_id             = module.hub.vnet_hub_id
  hub_vnet_name           = module.hub.vnet_hub_name
  hub_resource_group_name    = module.hub.resource_group_name
  key_vault_id               = module.hub.key_vault_id
  ssh_public_key_secret_name = "vm-admin-ssh-public-key"

  tags = {
    CostCenter = "Marketing"
    Owner      = "analytics-team@example.com"
  }
}
```

## 📥 Inputs

| Variable | Description | Type | Défaut | Requis |
|----------|-------------|------|--------|--------|
| `team_name` | Nom de l'équipe | `string` | - | ✅ |
| `project_name` | Nom du projet | `string` | - | ✅ |
| `location` | Région Azure | `string` | - | ✅ |
| `environments` | Liste des environnements | `list(string)` | - | ✅ |
| `address_spaces` | Map des CIDR par environnement | `map(string)` | - | ✅ |
| `hub_vnet_id` | ID du VNet Hub | `string` | - | ✅ |
| `hub_vnet_name` | Nom du VNet Hub | `string` | - | ✅ |
| `hub_resource_group_name` | Nom du RG réseau du Hub | `string` | - | ✅ |
| `key_vault_id` | ID du Key Vault contenant la clé publique SSH | `string` | - | ✅ |
| `ssh_public_key_secret_name` | Nom du secret contenant la clé publique SSH | `string` | - | ✅ |
| `vm_size` | Taille des VMs front/back | `string` | `"Standard_B2ts_v2"` | ❌ |
| `vm_count` | Nombre de VMs par service front/back | `object` | `{ front = 1, back = 1 }` | ❌ |
| `vm_environments` | Environnements où créer les VMs | `list(string)` | `["dev"]` | ❌ |
| `vm_admin_username` | Utilisateur admin Linux | `string` | `"azureuser"` | ❌ |
| `acr_id` | ID de l'ACR du Hub pour les role assignments | `string` | - | ✅ |
| `tags` | Tags additionnels | `map(string)` | `{}` | ❌ |

## 📤 Outputs

| Output | Description | Type |
|--------|-------------|------|
| `resource_group_ids` | IDs des resource groups créés | `map(string)` |
| `vnet_ids` | IDs des VNets créés | `map(string)` |
| `subnet_ids` | IDs des subnets créés | `map(object)` |
| `nsg_ids` | IDs des NSG créés | `map(object)` |

### Exemple d'utilisation des outputs

```hcl
# Récupérer l'ID du VNet de production
output "ecom_prod_vnet_id" {
  value = module.ecom.vnet_ids["prod"]
}

# Récupérer l'ID du subnet frontend de dev
output "ecom_dev_frontend_subnet_id" {
  value = module.ecom.subnet_ids["front"]["dev"]
}
```

## 🔒 Sécurité - Network Security Groups

### Frontend Subnet

**Ports autorisés :**
- ✅ HTTP (80) et HTTPS (443) depuis Internet
- ✅ SSH (22) **uniquement en dev/qua**

### Backend Subnet

**Ports autorisés :**
- ✅ API (8080) **uniquement depuis Frontend subnet**
- ✅ SSH (22) **uniquement en dev/qua**

### Data Subnet

**Ports autorisés :**
- ✅ PostgreSQL (5432) **uniquement depuis Backend subnet**
- ✅ SSH (22) **uniquement en dev/qua**
- ❌ **Internet sortant bloqué en production**

## 🗺️ Plan d'Adressage

Le module utilise la fonction `cidrsubnet()` pour calculer automatiquement les subnets :

```hcl
# Pour un VNet 10.1.0.0/16
Frontend: cidrsubnet("10.1.0.0/16", 8, 0) → 10.1.0.0/24
Backend:  cidrsubnet("10.1.0.0/16", 8, 1) → 10.1.1.0/24
Data:     cidrsubnet("10.1.0.0/16", 8, 2) → 10.1.2.0/24
```

### Exemple par Environnement

| Environnement | VNet | Frontend | Backend | Data |
|---------------|------|----------|---------|------|
| Dev | 10.1.0.0/16 | 10.1.0.0/24 | 10.1.1.0/24 | 10.1.2.0/24 |
| Qua | 10.2.0.0/16 | 10.2.0.0/24 | 10.2.1.0/24 | 10.2.2.0/24 |
| Prod | 10.3.0.0/16 | 10.3.0.0/24 | 10.3.1.0/24 | 10.3.2.0/24 |

Chaque subnet définit explicitement :

```hcl
private_endpoint_network_policies = "Enabled"
```

Ce réglage conserve le comportement existant côté Azure et évite qu'une valeur par défaut du provider déclenche des updates de subnets non souhaitées.

## 📦 Ressources Créées

Pour **1 Spoke avec 3 environnements** (dev, qua, prod) :

```
3 × Resource Groups
3 × VNets
9 × Subnets (3 par environnement)
9 × NSG (3 par environnement)
~27 × Règles NSG
6 × VNet Peerings (2 par environnement)
3 × Managed Identities (1 par environnement)
3 × Role Assignments AcrPull (1 par environnement)
2 × NICs privées si vm_count = { front = 1, back = 1 } et vm_environments = ["dev"]
2 × VMs Linux privées dans les subnets front/back de dev
```

## 🖥️ VMs, NICs et cloud-init

Les VMs sont créées à partir de `local.vm_instances`, calculé avec :

- `vm_environments` : environnements où provisionner des VMs
- `vm_count.front` : nombre de VMs frontend par environnement
- `vm_count.back` : nombre de VMs backend par environnement

Le module exclut volontairement `prod` des VMs générées par ce bloc, même si `prod` est présent dans `vm_environments`.

### Nommage

```text
Frontend VM : vm-formation-ecom-front-dev-01
Backend VM  : vm-formation-ecom-back-dev-01
Frontend NIC: nic-formation-ecom-front-dev-01
Backend NIC : nic-formation-ecom-back-dev-01
```

### Réseau

- Les NICs utilisent une IP privée dynamique.
- Aucune Public IP n'est créée.
- La VM front est attachée au subnet front.
- La VM back est attachée au subnet back.
- L'accès SSH direct depuis Internet n'est pas possible sans Bastion, VPN, jumpbox ou autre accès au VNet.

### Image et taille

```hcl
vm_size = "Standard_B2ts_v2"

source_image_reference {
  publisher = "Canonical"
  offer     = "0001-com-ubuntu-server-jammy"
  sku       = "22_04-lts-gen2"
  version   = "latest"
}
```

`vm_size` définit le hardware Azure. `source_image_reference` définit l'OS. Ici, les VMs sont des Ubuntu 22.04 Gen2.

### SSH

Le module lit la clé publique depuis Key Vault :

```hcl
data "azurerm_key_vault_secret" "admin_ssh_public_key" {
  name         = var.ssh_public_key_secret_name
  key_vault_id = var.key_vault_id
}
```

L'authentification password est désactivée :

```hcl
disable_password_authentication = true
```

### Docker

Docker est installé au premier boot via `custom_data` cloud-init :

- ajout du dépôt officiel Docker Ubuntu
- installation de `docker-ce`, `docker-ce-cli`, `containerd.io`, Buildx et Compose plugin
- activation du service Docker
- ajout de `vm_admin_username` au groupe `docker`

Pour vérifier l'installation :

```bash
az vm run-command invoke \
  -g rg-formation-ecom-dev \
  -n vm-formation-ecom-front-dev-01 \
  --command-id RunShellScript \
  --scripts "cloud-init status --long; docker --version; systemctl is-active docker; groups azureuser"
```

Pour lire les logs cloud-init :

```bash
az vm run-command invoke \
  -g rg-formation-ecom-dev \
  -n vm-formation-ecom-front-dev-01 \
  --command-id RunShellScript \
  --scripts "sudo tail -n 120 /var/log/cloud-init-output.log"
```

### Remplacer les VMs après modification du custom_data

`custom_data` force le remplacement de la VM. Pour recréer seulement les VMs front/back :

```bash
terraform apply \
  -replace='module.spoke.azurerm_linux_virtual_machine.vm["dev-front-01"]' \
  -replace='module.spoke.azurerm_linux_virtual_machine.vm["dev-back-01"]'
```

Les NICs peuvent rester en place si seul le script de boot change.

## 🔄 VNet Peering

Le module crée automatiquement les peerings bidirectionnels :

```
Hub VNet ←→ Spoke Dev VNet
Hub VNet ←→ Spoke Qua VNet
Hub VNet ←→ Spoke Prod VNet
```

**Configuration :**
- `allow_virtual_network_access = true`
- `allow_forwarded_traffic = false` (par défaut)
- `allow_gateway_transit = false` (par défaut)

## 📝 Nomenclature

Toutes les ressources suivent la convention de nommage définie dans [NOMENCLATURE.md](../../NOMENCLATURE.md).

**Format :** `{prefix}-{team}-{project}-{tier/env}`

**Exemples :**
```
Resource Groups:
  rg-formation-ecom-dev
  rg-formation-ecom-prod

VNets:
  vnet-formation-ecom-dev
  vnet-formation-ecom-prod

Subnets:
  subnet-front-dev
  subnet-back-prod

NSG:
  nsg-formation-ecom-front-dev
  nsg-formation-ecom-backend-prod
  nsg-formation-ecom-data-prod
```

## 🎯 Cas d'Usage

### Environnement de développement uniquement

```hcl
module "sandbox" {
  source = "./modules/spoke"

  project_name   = "sandbox"
  environments   = ["dev"]  # Un seul environnement
  address_spaces = {
    dev = "10.10.0.0/16"
  }
  # ... autres paramètres
}
```

### Projet avec 4 environnements

```hcl
module "critical-app" {
  source = "./modules/spoke"

  project_name   = "critical"
  environments   = ["dev", "qua", "preprod", "prod"]
  address_spaces = {
    dev     = "10.20.0.0/16"
    qua     = "10.21.0.0/16"
    preprod = "10.22.0.0/16"
    prod    = "10.23.0.0/16"
  }
  # ... autres paramètres
}
```

## ⚙️ Personnalisation

### Modifier les règles NSG

Les règles NSG sont dans `nsg.tf`. Pour ajouter une règle :

```hcl
# Exemple : Autoriser Redis en backend
resource "azurerm_network_security_rule" "back_redis" {
  for_each = toset(var.environments)

  name                        = "Allow-Redis-From-Frontend"
  priority                    = 130
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "6379"
  source_address_prefix       = local.subnets[each.key].front
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main[each.key].name
  network_security_group_name = azurerm_network_security_group.back[each.key].name
}
```

### Ajouter un 4ème subnet

Modifier `main.tf` pour ajouter un subnet "cache" :

```hcl
locals {
  subnets = {
    for env in var.environments : env => {
      front = cidrsubnet(var.address_spaces[env], 8, 0)
      back  = cidrsubnet(var.address_spaces[env], 8, 1)
      data  = cidrsubnet(var.address_spaces[env], 8, 2)
      cache = cidrsubnet(var.address_spaces[env], 8, 3)  # Nouveau
    }
  }
}

resource "azurerm_subnet" "subnet-cache" {
  for_each = toset(var.environments)

  name                 = "subnet-cache-${each.key}"
  resource_group_name  = azurerm_resource_group.main[each.key].name
  virtual_network_name = azurerm_virtual_network.main[each.key].name
  address_prefixes     = [local.subnets[each.key].cache]
}
```

## 🐛 Troubleshooting

### Erreur : Address space overlap

**Problème :** Les CIDR des environnements se chevauchent.

**Solution :** Vérifier que chaque environnement a un CIDR unique :
```hcl
address_spaces = {
  dev  = "10.1.0.0/16"  # ✅
  qua  = "10.2.0.0/16"  # ✅
  prod = "10.1.0.0/16"  # ❌ Conflit avec dev!
}
```

### Erreur : Peering already exists

**Problème :** Un peering existe déjà avec le même nom.

**Solution :** Vérifier les noms de peering dans le Hub. Utiliser des noms uniques par projet.

### Subnet trop petit

**Problème :** Un subnet /24 ne suffit pas (256 IPs).

**Solution :** Modifier le calcul dans `locals` :
```hcl
# Passer de /24 à /23 (512 IPs)
front = cidrsubnet(var.address_spaces[env], 7, 0)
```

## 📚 Ressources

- [Documentation Hub & Spoke](../../README.md)
- [Architecture détaillée](../../ARCHITECTURE.md)
- [Nomenclature](../../NOMENCLATURE.md)

---

**🔙 Retour au [README principal](../../README.md)**
