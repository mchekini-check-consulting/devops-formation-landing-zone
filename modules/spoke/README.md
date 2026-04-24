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

## 🏗️ Architecture

```
Spoke "ecom" avec 3 environnements
│
├── Dev (10.1.0.0/16)
│   ├── rg-formation-ecom-dev
│   ├── vnet-formation-ecom-dev
│   ├── subnet-front-dev (10.1.0.0/24) + NSG
│   ├── subnet-back-dev (10.1.1.0/24) + NSG
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
  hub_vnet_id             = module.hub.vnet_id
  hub_vnet_name           = module.hub.vnet_name
  hub_resource_group_name = module.hub.network_resource_group_name
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
  hub_vnet_id             = module.hub.vnet_id
  hub_vnet_name           = module.hub.vnet_name
  hub_resource_group_name = module.hub.network_resource_group_name

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

## 📦 Ressources Créées

Pour **1 Spoke avec 3 environnements** (dev, qua, prod) :

```
3 × Resource Groups
3 × VNets
9 × Subnets (3 par environnement)
9 × NSG (3 par environnement)
~27 × Règles NSG
6 × VNet Peerings (2 par environnement)
```

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
