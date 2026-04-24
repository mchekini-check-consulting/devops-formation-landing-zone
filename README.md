# 🌐 Landing Zone Azure - Hub & Spoke

Infrastructure as Code (Terraform) pour déployer une Landing Zone Azure avec architecture Hub & Spoke.

## 📋 Table des Matières

- [Vue d'ensemble](#vue-densemble)
- [Architecture](#architecture)
- [Structure du Projet](#structure-du-projet)
- [Prérequis](#prérequis)
- [Démarrage Rapide](#démarrage-rapide)
- [Configuration](#configuration)
- [Modules](#modules)
- [Sécurité](#sécurité)
- [Nomenclature](#nomenclature)
- [Documentation](#documentation)

---

## 🎯 Vue d'ensemble

Cette Landing Zone implémente une architecture **Hub & Spoke** sur Azure :

- **1 Hub** : Ressources partagées (monitoring, réseau, sécurité, devops)
- **N Spokes** : Un par projet, avec plusieurs environnements (dev, qua, prod)
- **Network Security Groups** : Sécurisation des flux réseau par tier
- **VNet Peering** : Connectivité Hub ↔ Spokes

### 🎯 Objectifs

✅ **Isolation** : Chaque projet a son propre réseau et environnements
✅ **Sécurité** : NSG par subnet avec règles différenciées dev/prod
✅ **Scalabilité** : Ajout facile de nouveaux projets
✅ **Gouvernance** : Nomenclature cohérente et tags standards
✅ **Automation** : Infrastructure as Code avec Terraform

---

## 🏗️ Architecture

### Architecture Réseau

```
┌─────────────────────────────────────────────────────────────┐
│                       HUB (10.0.0.0/16)                     │
│  ┌──────────────┐  ┌──────────┐  ┌──────────┐  ┌─────────┐ │
│  │  Monitoring  │  │  Network │  │ Security │  │  DevOps │ │
│  │  (RG)        │  │  (RG)    │  │  (RG)    │  │  (RG)   │ │
│  └──────────────┘  └──────────┘  └──────────┘  └─────────┘ │
│         VNet Hub : vnet-formation-hub                       │
└───────────────────────┬─────────────────────────────────────┘
                        │ VNet Peering
        ┌───────────────┼───────────────┐
        │               │               │
┌───────▼──────┐ ┌──────▼──────┐ ┌─────▼───────┐
│ SPOKE: ecom  │ │ SPOKE: ...  │ │ SPOKE: ...  │
│              │ │             │ │             │
│ ┌──────────┐ │ │             │ │             │
│ │   Dev    │ │ │             │ │             │
│ │ 10.1.0/16│ │ │             │ │             │
│ └──────────┘ │ │             │ │             │
│ ┌──────────┐ │ │             │ │             │
│ │   Qua    │ │ │             │ │             │
│ │ 10.2.0/16│ │ │             │ │             │
│ └──────────┘ │ │             │ │             │
│ ┌──────────┐ │ │             │ │             │
│ │   Prod   │ │ │             │ │             │
│ │ 10.3.0/16│ │ │             │ │             │
│ └──────────┘ │ │             │ │             │
└──────────────┘ └─────────────┘ └─────────────┘
```

### Détail d'un Spoke (par environnement)

```
┌─────────────────────────────────────────────────────────────┐
│           VNet Spoke : vnet-formation-ecom-dev              │
│                     (10.1.0.0/16)                           │
│                                                             │
│  ┌────────────────────────────────────────────────────┐    │
│  │  Subnet Frontend (10.1.0.0/24)                     │    │
│  │  NSG: nsg-formation-ecom-front-dev                 │    │
│  │  • HTTP/HTTPS: * → 80,443                          │    │
│  │  • SSH: * → 22 (dev/qua uniquement)                │    │
│  └────────────────────────────────────────────────────┘    │
│                          ↓                                  │
│  ┌────────────────────────────────────────────────────┐    │
│  │  Subnet Backend (10.1.1.0/24)                      │    │
│  │  NSG: nsg-formation-ecom-backend-dev               │    │
│  │  • API: 10.1.0.0/24 → 8080                         │    │
│  │  • SSH: * → 22 (dev/qua uniquement)                │    │
│  └────────────────────────────────────────────────────┘    │
│                          ↓                                  │
│  ┌────────────────────────────────────────────────────┐    │
│  │  Subnet Data (10.1.2.0/24)                         │    │
│  │  NSG: nsg-formation-ecom-data-dev                  │    │
│  │  • PostgreSQL: 10.1.1.0/24 → 5432                  │    │
│  │  • SSH: * → 22 (dev/qua uniquement)                │    │
│  │  • Deny Internet Outbound (prod uniquement)        │    │
│  └────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

**➡️ Voir [ARCHITECTURE.md](./ARCHITECTURE.md) pour les détails techniques**

---

## 📁 Structure du Projet

```
terraform-azure/
├── README.md                    # Ce fichier
├── NOMENCLATURE.md             # Conventions de nommage
├── ARCHITECTURE.md             # Architecture détaillée
├── main.tf                     # Point d'entrée principal
├── variables.tf                # Variables globales
├── outputs.tf                  # Outputs globaux
├── providers.tf                # Configuration provider Azure
├── terraform.tfvars            # Valeurs des variables
│
├── modules/
│   ├── hub/                    # Module Hub
│   │   ├── main.tf            # Resource Groups
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   └── spoke/                  # Module Spoke (par projet)
│       ├── main.tf            # Resource Groups + VNets + Subnets
│       ├── nsg.tf             # Network Security Groups
│       ├── peering.tf         # VNet Peering Hub ↔ Spoke
│       ├── variables.tf
│       └── outputs.tf
│
└── .gitignore
```

---

## ✅ Prérequis

### Outils requis

- **Terraform** >= 1.5.0
- **Azure CLI** >= 2.50.0
- **Compte Azure** avec les permissions appropriées

### Installation

#### macOS (Homebrew)
```bash
brew install terraform azure-cli
```

#### Linux
```bash
# Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

#### Windows (Chocolatey)
```powershell
choco install terraform azure-cli
```

### Authentification Azure

```bash
# Se connecter à Azure
az login

# Vérifier l'abonnement actif
az account show

# (Optionnel) Changer d'abonnement
az account set --subscription "SUBSCRIPTION_ID"
```

---

## 🚀 Démarrage Rapide

### 1. Cloner le projet

```bash
git clone <repository-url>
cd terraform-azure
```

### 2. Configurer les variables

Éditer `terraform.tfvars` :

```hcl
team_name = "formation"
location  = "francecentral"
```

### 3. Initialiser Terraform

```bash
terraform init
```

### 4. Prévisualiser les changements

```bash
terraform plan
```

### 5. Déployer l'infrastructure

```bash
terraform apply
```

### 6. Vérifier le déploiement

```bash
# Lister les resource groups créés
az group list --query "[?starts_with(name, 'rg-formation')].name" -o table

# Vérifier les VNets
az network vnet list --query "[?starts_with(name, 'vnet-formation')].{Name:name, AddressSpace:addressSpace.addressPrefixes[0]}" -o table
```

---

## ⚙️ Configuration

### Variables principales

| Variable | Description | Type | Défaut |
|----------|-------------|------|--------|
| `team_name` | Nom de l'équipe | `string` | `"formation"` |
| `location` | Région Azure | `string` | `"francecentral"` |
| `environments` | Liste des environnements | `list(string)` | `["dev", "qua", "prod"]` |
| `hub_address_space` | Plage IP du Hub | `string` | `"10.0.0.0/16"` |
| `spoke_address_spaces` | Plages IP des Spokes | `map(string)` | Voir ci-dessous |

### Plan d'adressage IP par défaut

```hcl
spoke_address_spaces = {
  dev  = "10.1.0.0/16"
  qua  = "10.2.0.0/16"
  prod = "10.3.0.0/16"
}
```

Chaque environnement est subdivisé en 3 subnets :
- Frontend : `10.x.0.0/24`
- Backend : `10.x.1.0/24`
- Data : `10.x.2.0/24`

---

## 📦 Modules

### Module Hub

Crée les ressources partagées :
- 4 Resource Groups (monitoring, network, security, devops)
- 1 VNet Hub (10.0.0.0/16)

**Utilisation :**
```hcl
module "hub" {
  source = "./modules/hub"

  team_name     = var.team_name
  location      = var.location
  address_space = var.hub_address_space
}
```

### Module Spoke

Crée un projet avec ses environnements :
- N Resource Groups (1 par environnement)
- N VNets (1 par environnement)
- 3N Subnets (3 par environnement)
- 3N NSG (3 par environnement)
- 2N VNet Peerings (2 par environnement)

**Utilisation :**
```hcl
module "ecom" {
  source = "./modules/spoke"

  team_name               = var.team_name
  project_name            = "ecom"
  location                = var.location
  environments            = var.environments
  address_spaces          = var.spoke_address_spaces
  hub_vnet_id             = module.hub.vnet_id
  hub_vnet_name           = module.hub.vnet_name
  hub_resource_group_name = module.hub.network_resource_group_name
}
```

---

## 🔒 Sécurité

### Network Security Groups (NSG)

Chaque subnet a son propre NSG avec des règles spécifiques :

#### Frontend
- ✅ HTTP (80) et HTTPS (443) depuis Internet
- ✅ SSH (22) en dev/qua uniquement
- ❌ SSH bloqué en production

#### Backend
- ✅ API (8080) depuis le subnet frontend uniquement
- ✅ SSH (22) en dev/qua uniquement
- ❌ SSH bloqué en production

#### Data
- ✅ PostgreSQL (5432) depuis le subnet backend uniquement
- ✅ SSH (22) en dev/qua uniquement
- ❌ SSH bloqué en production
- ❌ Internet sortant bloqué en production

### Recommandations de sécurité

⚠️ **Pour la production, il est recommandé de :**

1. **Utiliser Azure Bastion** pour l'administration au lieu de SSH direct
2. **Restreindre les sources HTTP/HTTPS** avec Azure Front Door ou Application Gateway
3. **Activer Azure Defender** pour la protection avancée
4. **Configurer Azure Monitor** pour la surveillance
5. **Utiliser Azure Key Vault** pour les secrets

---

## 📝 Nomenclature

Toutes les ressources suivent une convention de nommage stricte.

**Format général :** `{prefix}-{team}-{projet}-{fonction/env}`

### Exemples

```
Resource Groups:
  rg-formation-monitoring
  rg-formation-ecom-dev
  rg-formation-ecom-prod

VNets:
  vnet-formation-hub
  vnet-formation-ecom-dev
  vnet-formation-ecom-prod

Subnets:
  subnet-front-dev
  subnet-back-dev
  subnet-data-dev

NSG:
  nsg-formation-ecom-front-dev
  nsg-formation-ecom-backend-prod
  nsg-formation-ecom-data-prod
```

**➡️ Voir [NOMENCLATURE.md](./NOMENCLATURE.md) pour tous les détails**

---

## 📚 Documentation

- **[NOMENCLATURE.md](./NOMENCLATURE.md)** - Conventions de nommage complètes
- **[ARCHITECTURE.md](./ARCHITECTURE.md)** - Architecture technique détaillée

---

## 🔄 Ajouter un Nouveau Projet

Pour ajouter un nouveau projet (exemple : "analytics") :

1. **Ajouter le module dans `main.tf`** :

```hcl
module "analytics" {
  source = "./modules/spoke"

  team_name               = var.team_name
  project_name            = "analytics"
  location                = var.location
  environments            = var.environments
  address_spaces          = var.spoke_address_spaces
  hub_vnet_id             = module.hub.vnet_id
  hub_vnet_name           = module.hub.vnet_name
  hub_resource_group_name = module.hub.network_resource_group_name
}
```

2. **Appliquer les changements** :

```bash
terraform plan
terraform apply
```

Cela créera automatiquement :
- 3 Resource Groups (dev, qua, prod)
- 3 VNets avec leurs subnets
- 9 NSG (3 par environnement)
- 6 VNet Peerings

---

## 🧹 Nettoyage

Pour détruire toute l'infrastructure :

```bash
# Prévisualiser ce qui sera détruit
terraform plan -destroy

# Détruire l'infrastructure
terraform destroy
```

⚠️ **Attention** : Cette action est irréversible !

---

## 📊 Coûts

Cette Landing Zone de base est **quasi-gratuite** :

| Ressource | Coût mensuel |
|-----------|--------------|
| Resource Groups | 🆓 Gratuit |
| VNets | 🆓 Gratuit |
| Subnets | 🆓 Gratuit |
| NSG | 🆓 Gratuit |
| VNet Peering (même région) | 🆓 Gratuit |

**Total estimé : 0€/mois**

Les coûts réels dépendront des ressources déployées (VMs, App Services, bases de données, etc.).


---

## 📄 Licence

Ce projet est fourni à des fins éducatives.

---

## 👥 Auteurs

- Équipe Formation

---

## 🆘 Support

Pour toute question ou problème :

1. Consulter la [documentation](./ARCHITECTURE.md)
2. Vérifier les [issues GitHub](../../issues)
3. Créer une nouvelle issue si nécessaire
