# Module Hub

Module Terraform pour créer le **Hub** dans l'architecture Hub & Spoke.

Le Hub centralise les **services partagés** utilisés par tous les Spokes (projets).

## 📋 Vue d'ensemble

Ce module crée :
- ✅ 4 Resource Groups (monitoring, network, security, devops)
- ✅ 1 VNet Hub
- ✅ Infrastructure prête pour les services partagés

## 🏗️ Architecture

```
Hub (10.0.0.0/16)
│
├── rg-formation-monitoring   # Monitoring centralisé
│   └── Log Analytics, Application Insights (à déployer)
│
├── rg-formation-network      # Réseau Hub
│   └── vnet-formation-hub
│       ├── (Futur) Subnet Firewall
│       ├── (Futur) Subnet VPN Gateway
│       └── (Futur) Subnet Bastion
│
├── rg-formation-security     # Sécurité
│   └── Key Vault, Sentinel (à déployer)
│
└── rg-formation-devops       # DevOps
    └── Container Registry, Artifact Store (à déployer)
```

## 📁 Structure du Module

```
modules/hub/
├── main.tf         # Resource Groups + VNet Hub
├── variables.tf    # Variables d'entrée
├── outputs.tf      # Outputs
└── README.md       # Ce fichier
```

## 🔧 Utilisation

### Exemple Basique

```hcl
module "hub" {
  source = "./modules/hub"

  team_name     = "formation"
  location      = "francecentral"
  address_space = "10.0.0.0/16"
}
```

### Exemple avec Tags Personnalisés

```hcl
module "hub" {
  source = "./modules/hub"

  team_name     = "formation"
  location      = "francecentral"
  address_space = "10.0.0.0/16"

  tags = {
    Environment = "shared"
    CostCenter  = "IT"
    Owner       = "platform-team@example.com"
  }
}
```

## 📥 Inputs

| Variable | Description | Type | Défaut | Requis |
|----------|-------------|------|--------|--------|
| `team_name` | Nom de l'équipe | `string` | - | ✅ |
| `location` | Région Azure | `string` | `"francecentral"` | ❌ |
| `address_space` | CIDR du VNet Hub | `string` | `"10.0.0.0/16"` | ❌ |
| `tags` | Tags additionnels | `map(string)` | `{}` | ❌ |

## 📤 Outputs

| Output | Description |
|--------|-------------|
| `vnet_id` | ID du VNet Hub |
| `vnet_name` | Nom du VNet Hub |
| `network_resource_group_name` | Nom du RG réseau (pour peering) |
| `monitoring_resource_group_name` | Nom du RG monitoring |
| `security_resource_group_name` | Nom du RG security |
| `devops_resource_group_name` | Nom du RG devops |

### Exemple d'utilisation des outputs

```hcl
# Utiliser les outputs du Hub dans un Spoke
module "ecom" {
  source = "./modules/spoke"

  # ... autres paramètres
  hub_vnet_id             = module.hub.vnet_id
  hub_vnet_name           = module.hub.vnet_name
  hub_resource_group_name = module.hub.network_resource_group_name
}
```

## 📦 Resource Groups Créés

### 1. RG Monitoring (`rg-formation-monitoring`)

**Fonction :** Monitoring et observabilité centralisés

**Services recommandés :**
- ✅ Log Analytics Workspace
- ✅ Application Insights
- ✅ Azure Monitor Alerts
- ✅ Dashboards partagés

**Exemple de déploiement :**
```hcl
resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-formation-monitoring"
  location            = module.hub.monitoring_resource_group_location
  resource_group_name = module.hub.monitoring_resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}
```

### 2. RG Network (`rg-formation-network`)

**Fonction :** Infrastructure réseau centralisée

**Services recommandés :**
- ✅ VNet Hub (déjà créé)
- ✅ Azure Firewall (optionnel)
- ✅ VPN Gateway (optionnel)
- ✅ Azure Bastion (optionnel)
- ✅ Network Watcher

**Exemple avec Azure Bastion :**
```hcl
resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"  # Nom imposé par Azure
  resource_group_name  = module.hub.network_resource_group_name
  virtual_network_name = module.hub.vnet_name
  address_prefixes     = ["10.0.0.0/26"]
}

resource "azurerm_bastion_host" "main" {
  name                = "bastion-formation-hub"
  location            = var.location
  resource_group_name = module.hub.network_resource_group_name

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }
}
```

### 3. RG Security (`rg-formation-security`)

**Fonction :** Sécurité et gestion des secrets

**Services recommandés :**
- ✅ Azure Key Vault
- ✅ Azure Sentinel (SIEM)
- ✅ Azure Policy
- ✅ Microsoft Defender for Cloud

**Exemple Key Vault :**
```hcl
resource "azurerm_key_vault" "main" {
  name                = "kv-formation-security"
  location            = var.location
  resource_group_name = module.hub.security_resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  enable_rbac_authorization = true
}
```

### 4. RG DevOps (`rg-formation-devops`)

**Fonction :** Outils et services DevOps

**Services recommandés :**
- ✅ Azure Container Registry
- ✅ Azure DevOps Artifacts
- ✅ Self-hosted agents

**Exemple Container Registry :**
```hcl
resource "azurerm_container_registry" "main" {
  name                = "crformationdevops"
  location            = var.location
  resource_group_name = module.hub.devops_resource_group_name
  sku                 = "Basic"
  admin_enabled       = false
}
```

## 🗺️ Plan d'Adressage

### VNet Hub par défaut

```
VNet Hub: 10.0.0.0/16 (65,536 IPs)
│
├── (Futur) Subnet Bastion:      10.0.0.0/26   (64 IPs)
├── (Futur) Subnet Firewall:     10.0.1.0/26   (64 IPs)
├── (Futur) Subnet VPN Gateway:  10.0.2.0/26   (64 IPs)
└── (Réservé pour autres usages) 10.0.3.0+
```

**Note :** Le VNet Hub est créé sans subnet. Vous pouvez ajouter les subnets selon vos besoins.

## 🔌 Connectivité avec les Spokes

Les Spokes se connectent automatiquement au Hub via **VNet Peering**.

```
Hub VNet (10.0.0.0/16)
    ↕ VNet Peering
Spoke VNets (10.x.0.0/16)
```

**Configuration par défaut :**
- ✅ `allow_virtual_network_access = true`
- ❌ `allow_forwarded_traffic = false`
- ❌ `allow_gateway_transit = false`

## 🎯 Cas d'Usage

### Hub Minimal (actuel)

Pour commencer simplement :
```hcl
module "hub" {
  source = "./modules/hub"

  team_name = "formation"
  location  = "francecentral"
}
```

Crée uniquement les Resource Groups et le VNet Hub.

### Hub avec Azure Bastion

Pour l'administration sécurisée :
```hcl
module "hub" {
  source = "./modules/hub"

  team_name = "formation"
  location  = "francecentral"
}

# Ajouter Bastion dans le VNet Hub
resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = module.hub.network_resource_group_name
  virtual_network_name = module.hub.vnet_name
  address_prefixes     = ["10.0.0.0/26"]
}

# ... Configuration Bastion
```

### Hub avec Azure Firewall

Pour filtrer le trafic :
```hcl
module "hub" {
  source = "./modules/hub"

  team_name = "formation"
  location  = "francecentral"
}

# Ajouter Firewall subnet
resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"  # Nom imposé
  resource_group_name  = module.hub.network_resource_group_name
  virtual_network_name = module.hub.vnet_name
  address_prefixes     = ["10.0.1.0/26"]
}

# ... Configuration Firewall
```

## 📝 Nomenclature

Toutes les ressources suivent la convention définie dans [NOMENCLATURE.md](../../NOMENCLATURE.md).

**Format :** `{prefix}-{team}-{fonction}`

**Exemples :**
```
Resource Groups:
  rg-formation-monitoring
  rg-formation-network
  rg-formation-security
  rg-formation-devops

VNet:
  vnet-formation-hub
```

## 🔄 Évolution

### Ajouter un Service Partagé

1. **Identifier le RG approprié**
   - Monitoring → `rg-formation-monitoring`
   - Réseau → `rg-formation-network`
   - Sécurité → `rg-formation-security`
   - DevOps → `rg-formation-devops`

2. **Déployer le service**

Exemple Log Analytics :
```hcl
resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-formation-monitoring"
  location            = var.location
  resource_group_name = module.hub.monitoring_resource_group_name
  sku                 = "PerGB2018"
}
```

3. **Configurer les Spokes pour l'utiliser**

```hcl
# Envoyer les logs des NSG vers Log Analytics
resource "azurerm_monitor_diagnostic_setting" "nsg" {
  name                       = "nsg-diagnostics"
  target_resource_id         = azurerm_network_security_group.front.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  log {
    category = "NetworkSecurityGroupEvent"
    enabled  = true
  }
}
```

## 💰 Coûts

### Ressources actuelles (Gratuites)

| Ressource | Coût |
|-----------|------|
| Resource Groups | 🆓 Gratuit |
| VNet Hub | 🆓 Gratuit |

**Total : 0€/mois**

### Services optionnels (Payants)

| Service | Coût estimé/mois |
|---------|------------------|
| Azure Bastion | ~135€ |
| Azure Firewall | ~700€ |
| VPN Gateway | ~30-300€ |
| Log Analytics | Variable (données ingérées) |
| Key Vault | ~5€ |
| Container Registry | ~5-20€ |

## 🐛 Troubleshooting

### Le VNet Hub n'a pas de subnets

**Normal !** Le Hub VNet est créé vide par défaut.

**Solution :** Ajouter les subnets selon vos besoins (Bastion, Firewall, etc.).

### Les Spokes ne peuvent pas communiquer entre eux

**Problème :** Par défaut, les Spokes ne peuvent communiquer qu'avec le Hub.

**Solution :** Pour permettre la communication Spoke-to-Spoke :
- Option 1 : Activer `allow_forwarded_traffic` sur les peerings
- Option 2 : Déployer Azure Firewall dans le Hub pour router le trafic
- Option 3 : Créer des peerings directs Spoke-to-Spoke (non recommandé)

### Erreur de quota Azure

**Problème :** Limite de ressources atteinte dans la région.

**Solution :**
- Demander une augmentation de quota via le portail Azure
- Changer de région (modifier la variable `location`)

## 📚 Ressources

- [Documentation Hub & Spoke](../../README.md)
- [Architecture détaillée](../../ARCHITECTURE.md)
- [Nomenclature](../../NOMENCLATURE.md)

### Références Microsoft

- [Hub-spoke topology](https://learn.microsoft.com/azure/architecture/reference-architectures/hybrid-networking/hub-spoke)
- [Shared services pattern](https://learn.microsoft.com/azure/architecture/patterns/shared-service)

---

**🔙 Retour au [README principal](../../README.md)**
