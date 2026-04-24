# Nomenclature Azure - Landing Zone

Ce document décrit les conventions de nommage utilisées pour toutes les ressources Azure du projet.

## Principes Généraux

- **Préfixes standards** : Chaque type de ressource a un préfixe normalisé (ex: `rg-`, `vnet-`, `snet-`)
- **Séparateur** : Le tiret `-` est utilisé comme séparateur
- **Casse** : Tout en minuscules pour éviter les erreurs
- **Hiérarchie** : team → projet → fonction/environnement

## Resource Groups

### Hub (Ressources Partagées)

Les ressources du Hub sont organisées par fonction métier :

```
rg-{team}-{fonction}
```

**Exemples :**
```
rg-formation-monitoring      # Monitoring centralisé (Log Analytics, App Insights)
rg-formation-network         # Réseau Hub (VNet, Firewall, VPN Gateway)
rg-formation-security        # Sécurité (Key Vault, Sentinel)
rg-formation-devops          # DevOps (Container Registry, Artifact Store)
```

### Spoke (Par Projet)

Chaque projet a ses propres Resource Groups par environnement :

```
rg-{team}-{projet}-{environnement}
```

**Exemples :**
```
rg-formation-ecom-dev        # E-commerce - Développement
rg-formation-ecom-qua        # E-commerce - Qualification
rg-formation-ecom-prod       # E-commerce - Production

rg-formation-analytics-dev   # Analytics - Développement
rg-formation-analytics-qua   # Analytics - Qualification
rg-formation-analytics-prod  # Analytics - Production
```

## Virtual Networks (VNet)

### Hub VNet

```
vnet-{team}-hub
```

**Exemple :**
```
vnet-formation-hub           # VNet Hub (10.0.0.0/16)
```

### Spoke VNet

```
vnet-{team}-{projet}-{environnement}
```

**Exemples :**
```
vnet-formation-ecom-dev      # VNet E-commerce Dev (10.1.0.0/16)
vnet-formation-ecom-qua      # VNet E-commerce Qua (10.2.0.0/16)
vnet-formation-ecom-prod     # VNet E-commerce Prod (10.3.0.0/16)
```

## Subnets

### Convention

```
snet-{fonction}
```

Les subnets utilisent un nom fonctionnel car ils sont déjà dans un VNet spécifique.

**Exemples :**
```
snet-front                   # Subnet Frontend (x.x.0.0/24)
snet-backend                 # Subnet Backend (x.x.1.0/24)
snet-data                    # Subnet Data (x.x.2.0/24)
```

**Exemple complet pour le projet ecom-dev :**
- VNet : `vnet-formation-ecom-dev` (10.1.0.0/16)
  - `snet-front` (10.1.0.0/24)
  - `snet-backend` (10.1.1.0/24)
  - `snet-data` (10.1.2.0/24)

## Network Security Groups (NSG)

### Convention

```
nsg-{team}-{projet}-{tier}-{environnement}
```

Un NSG par subnet pour une isolation par tier (frontend, backend, data).

**Exemples :**
```
nsg-formation-ecom-front-dev       # NSG Frontend - Dev
nsg-formation-ecom-backend-dev     # NSG Backend - Dev
nsg-formation-ecom-data-dev        # NSG Data - Dev

nsg-formation-ecom-front-prod      # NSG Frontend - Prod
nsg-formation-ecom-backend-prod    # NSG Backend - Prod
nsg-formation-ecom-data-prod       # NSG Data - Prod
```

### Règles de Sécurité par Tier

#### Frontend (snet-front)

| Règle | Direction | Port | Protocol | Source | Dev/Qua | Prod |
|-------|-----------|------|----------|--------|---------|------|
| HTTP | Inbound | 80 | TCP | * | ✅ | ✅ |
| HTTPS | Inbound | 443 | TCP | * | ✅ | ✅ |
| SSH | Inbound | 22 | TCP | * | ✅ | ❌ |

**Usage :** Applications web, reverse proxy, load balancers

#### Backend (snet-backend)

| Règle | Direction | Port | Protocol | Source | Dev/Qua | Prod |
|-------|-----------|------|----------|--------|---------|------|
| API | Inbound | 8080 | TCP | Frontend subnet | ✅ | ✅ |
| SSH | Inbound | 22 | TCP | * | ✅ | ❌ |

**Usage :** APIs, microservices, application servers

#### Data (snet-data)

| Règle | Direction | Port | Protocol | Source | Dev/Qua | Prod |
|-------|-----------|------|----------|--------|---------|------|
| PostgreSQL | Inbound | 5432 | TCP | Backend subnet | ✅ | ✅ |
| SSH | Inbound | 22 | TCP | * | ✅ | ❌ |
| Internet | Outbound | * | * | Internet | ✅ | ❌ (Deny) |

**Usage :** Bases de données, stockage

### Stratégie de Sécurité par Environnement

**Dev/Qua (Développement et Qualification) :**
- Règles plus permissives pour faciliter le développement
- SSH autorisé depuis toutes sources (`*`)
- Accès HTTP/HTTPS depuis toutes sources (`*`)
- Accès Internet sortant autorisé

**Prod (Production) :**
- Règles strictes et restrictives
- Pas d'accès SSH direct
- Accès HTTP/HTTPS depuis toutes sources (`*`)
- Tier Data : Internet sortant bloqué

### Bonnes Pratiques

✅ **Un NSG par subnet** : Isolation claire par tier
✅ **Principe du moindre privilège** : Autoriser uniquement le nécessaire
✅ **Source spécifique** : Utiliser les CIDR des subnets pour les communications inter-tiers
✅ **Pas de SSH en prod** : Utiliser Azure Bastion pour l'administration
✅ **Deny Internet Outbound** : Pour le tier Data en production

⚠️ **Note de sécurité** : Pour une sécurité renforcée en production, envisagez :
- **Azure Front Door / Application Gateway** pour filtrer le trafic HTTP/HTTPS
- **Azure Bastion** pour l'administration au lieu de SSH direct
- **Service Tags Azure** pour des sources plus spécifiques (ex: `AzureLoadBalancer`, `VirtualNetwork`)
- **Plages IP spécifiques** pour limiter l'accès à votre entreprise uniquement

### Association NSG-Subnet

Chaque NSG est automatiquement associé à son subnet via :
```hcl
azurerm_subnet_network_security_group_association
```

**Exemple :**
- `nsg-formation-ecom-front-dev` → `snet-front` (dans vnet-formation-ecom-dev)
- `nsg-formation-ecom-backend-dev` → `snet-backend` (dans vnet-formation-ecom-dev)
- `nsg-formation-ecom-data-dev` → `snet-data` (dans vnet-formation-ecom-dev)

## VNet Peering

### Convention

```
peer-{source}-to-{destination}
```

**Exemples :**
```
peer-hub-to-ecom-dev         # Hub → E-commerce Dev
peer-ecom-dev-to-hub         # E-commerce Dev → Hub
peer-hub-to-ecom-prod        # Hub → E-commerce Prod
peer-ecom-prod-to-hub        # E-commerce Prod → Hub
```

## Autres Ressources Azure

### Network Security Group (NSG)
```
nsg-{team}-{projet}-{tier}-{env}

Exemple : nsg-formation-ecom-front-dev
```

### Storage Account
```
st{team}{projet}{env}{random}

Exemple : stecomdev01
```
Note : Les Storage Accounts n'acceptent pas les tirets et ont une limite de 24 caractères.

### Key Vault
```
kv-{team}-{projet}-{env}

Exemple : kv-formation-ecom-prod
```

### App Service / Function App
```
app-{team}-{projet}-{fonction}-{env}

Exemple : app-formation-ecom-api-prod
```

### Container Registry
```
cr{team}{projet}{env}

Exemple : crformationecomprod
```

### Log Analytics Workspace
```
log-{team}-{fonction}

Exemple : log-formation-monitoring
```

### Application Insights
```
appi-{team}-{projet}-{env}

Exemple : appi-formation-ecom-prod
```

## Environnements Standards

| Code | Nom Complet | Usage |
|------|-------------|-------|
| `dev` | Développement | Environnement de développement |
| `qua` | Qualification | Tests et validation (équivalent staging) |
| `prod` | Production | Environnement de production |

## Plan d'Adressage IP

### Hub
```
10.0.0.0/16                  # Réseau Hub
```

### Spokes
```
10.x.0.0/16                  # x = numéro basé sur l'environnement
  ├─ 10.x.0.0/24             # Frontend (subnet 0)
  ├─ 10.x.1.0/24             # Backend (subnet 1)
  └─ 10.x.2.0/24             # Data (subnet 2)
```

**Allocation par environnement :**
- Dev : 10.1.0.0/16
- Qua : 10.2.0.0/16
- Prod : 10.3.0.0/16

## Tags Standards

Tous les ressources incluent ces tags :

```hcl
Team        = "formation"
Project     = "ecom"           # Pour les Spokes uniquement
Environment = "dev"            # Pour les Spokes uniquement
Function    = "monitoring"     # Pour le Hub uniquement
Tier        = "frontend"       # Pour les NSG uniquement (frontend/backend/data)
ManagedBy   = "Terraform"
```

## Ajout d'un Nouveau Projet

Pour ajouter un nouveau projet (ex: "analytics") :

1. Ajouter le module dans `main.tf` :
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

2. Les ressources suivantes seront créées automatiquement :

**Resource Groups :**
```
rg-formation-analytics-dev
rg-formation-analytics-qua
rg-formation-analytics-prod
```

**VNets :**
```
vnet-formation-analytics-dev (10.1.0.0/16)
vnet-formation-analytics-qua (10.2.0.0/16)
vnet-formation-analytics-prod (10.3.0.0/16)
```

**Subnets :** (dans chaque VNet)
```
snet-front      (10.x.0.0/24)
snet-backend    (10.x.1.0/24)
snet-data       (10.x.2.0/24)
```

**Network Security Groups :**
```
nsg-formation-analytics-front-{env}
nsg-formation-analytics-backend-{env}
nsg-formation-analytics-data-{env}
```

**VNet Peerings :**
```
peer-hub-to-analytics-{env}
peer-analytics-{env}-to-hub
```

## Références

- [Azure Cloud Adoption Framework - Naming Convention](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming)
- [Azure Resource Abbreviations](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations)