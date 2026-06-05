# ADR-001 — Provisionnement AKS via Terraform

| Champ    | Valeur                                        |
|----------|-----------------------------------------------|
| Statut   | Accepté                                       |
| Date     | 2026-05-30                                    |
| Auteur   | elGiordano                                    |
| Contexte | Phase 04 — Provisionnement cluster AKS ecom   |

---

## Contexte

Le projet `ecom` nécessite un cluster Kubernetes managé sur Azure pour héberger :
- Des workloads applicatifs (APIs, microservices) dans le namespace `dev`
- Un cluster PostgreSQL répliqué via StatefulSet (3 pods, PVC Azure Disk)
- Un NGINX Ingress Controller exposant les services vers Internet

L'infrastructure est entièrement gérée par Terraform (`modules/aks/`). Le cluster est appelé depuis `main.tf` :
```hcl
module "aks" {
  source       = "./modules/aks"
  team_name    = var.team_name   # "formation"
  project_name = "ecom"
  location     = var.location    # "francecentral"
}
```

---

## Ressources créées par le module

```
modules/aks/
  ├── main.tf        → Resource Group + VNet + Subnet
  ├── cluster.tf     → Cluster AKS + node pool system
  ├── nodepools.tf   → Node pool apps + node pool db
  ├── variables.tf   → Variables avec défauts
  └── outputs.tf     → kubeconfig (sensitive)
```

---

## Décisions et justifications

---

### 1. Naming convention

**Décision** : `aks-${team_name}-${project_name}` → `aks-formation-ecom`

**Ressources nommées selon le même schéma :**

| Ressource | Nom généré |
|---|---|
| Resource Group | `rg-formation-ecom-aks` |
| VNet | `vnet-formation-ecom-aks` |
| Subnet | `subnet-aks` |
| Cluster AKS | `aks-formation-ecom` |

**Pourquoi :** cohérence avec la nomenclature du projet (voir `NOMENCLATURE.md`). Les variables `team_name` et `project_name` permettent de réutiliser le module pour d'autres projets sans modification.

---

### 2. Réseau dédié — VNet + Subnet

**Décision** : VNet `10.4.0.0/16` avec un seul subnet `10.4.0.0/22` pour tous les node pools.

```
VNet AKS : 10.4.0.0/16   (65 536 IPs)
  └── subnet-aks : 10.4.0.0/22  (1 024 IPs)
       ├── node pool system  (1 nœud)
       ├── node pool apps    (3-6 nœuds)
       └── node pool db      (2 nœuds)
```

**Pourquoi un VNet dédié :**
- Isolation réseau du cluster AKS par rapport au Hub et aux Spokes
- Le peering VNet vers le Hub peut être ajouté ultérieurement si les workloads AKS doivent accéder aux services partagés (APIM, Keycloak)
- `10.4.0.0/16` est dans le plan d'adressage réservé aux nouveaux projets (voir `ARCHITECTURE.md`)

**Pourquoi `/22` pour le subnet :**
- Avec Azure CNI, chaque pod reçoit une IP du subnet — pas seulement les nœuds
- 1 024 IPs = suffisant pour 9 nœuds × ~30 pods max par nœud (270 pods) + marge

---

### 3. Identity SystemAssigned

**Décision** : `identity { type = "SystemAssigned" }`.

**Pourquoi :**
- Identité managée créée et gérée automatiquement par Azure — pas de credentials à stocker ou rotation manuelle
- AKS utilise cette identité pour provisionner les ressources Azure en son nom : Load Balancers, Azure Disk (PVC), IP publiques
- Alternative `UserAssigned` : permet de pré-créer l'identité et d'assigner les rôles avant la création du cluster, utile en entreprise pour le contrôle d'accès strict — hors périmètre formation

---

### 4. `private_cluster_enabled = false`

**Décision** : API server accessible depuis Internet (cluster public).

**Pourquoi :**
- Contexte formation : les développeurs accèdent au cluster depuis leurs postes sans VPN ni Azure Bastion
- Un cluster privé (`private_cluster_enabled = true`) nécessite un accès réseau au VNet pour atteindre l'API server — requiert un jump host ou un VPN

**Limite :** l'API server Kubernetes est exposé sur Internet. En production, activer le cluster privé ou restreindre les IPs autorisées via `api_server_authorized_ip_ranges`.

---

### 5. Trois node pools distincts

**Décision** : séparer les workloads en trois pools dédiés.

```
system (default_node_pool)
  ├── 1 nœud fixe, Standard_B2s_v2
  ├── only_critical_addons_enabled = true
  └── rôle : composants système Kubernetes uniquement
             (kube-system : CoreDNS, kube-proxy, metrics-server...)

apps (azurerm_kubernetes_cluster_node_pool)
  ├── 3-6 nœuds, Standard_B2s_v2, autoscaling
  ├── pas de taint
  └── rôle : workloads applicatifs (NGINX, microservices, namespace dev)

db (azurerm_kubernetes_cluster_node_pool)
  ├── 2 nœuds fixes, Standard_B2s_v2, pas d'autoscaling
  ├── taint : workload=database:NoSchedule
  ├── label : workload=database
  └── rôle : PostgreSQL StatefulSet exclusivement
```

**Pourquoi cette séparation :**

| Critère | Pool unique | 3 pools séparés |
|---|---|---|
| Isolation système/app | Non | Oui — system pool protégé |
| Isolation DB/app | Non | Oui — taint empêche tout autre pod |
| Dimensionnement adapté | Non | Oui — DB fixe, apps élastique |
| Coût | Mutualisé | Légèrement plus élevé |

---

### 6. Node pool `system` : `only_critical_addons_enabled = true`

**Décision** : réserver le pool system aux seuls composants critiques Kubernetes.

**Pourquoi :**
- Sans ce flag, les pods applicatifs peuvent être schedulés sur le nœud system, créant une contention avec CoreDNS et kube-proxy
- Kubernetes pose automatiquement le taint `CriticalAddonsOnly=true:NoSchedule` sur les nœuds system — seuls les pods avec la toleration correspondante y sont admis
- `temporary_name_for_rotation = "systemtmp"` : permet à Terraform de remplacer le pool system (opération destructive) sans downtime — crée `systemtmp`, migre les pods, supprime `system`

---

### 7. Node pool `apps` : autoscaling 3-6 nœuds

**Décision** : `auto_scaling_enabled = true`, `min_count = 3`, `max_count = 6`.

**Pourquoi :**
- 3 nœuds minimum garantit la HA : si un nœud est evincé, les pods sont redistribués sur les 2 restants
- Autoscaling : AKS Cluster Autoscaler monte à 6 nœuds si les pods ne peuvent pas être schedulés (Pending), redescend à 3 quand la charge baisse
- `Standard_B2s_v2` (2 vCPU, 4 GB RAM) : gabarit économique adapté à la formation

---

### 8. Node pool `db` : taint + label, pas d'autoscaling

**Décision** : 2 nœuds fixes, taint `workload=database:NoSchedule`, label `workload=database`.

**Pourquoi le taint :**
- `NoSchedule` : tout pod sans la toleration `workload=database:NoSchedule` est interdit sur ces nœuds
- Garantit que les nœuds DB ne sont pas partagés avec des workloads applicatifs — isolation des ressources CPU/mémoire/IO pour PostgreSQL

**Pourquoi le label :**
- Complément du taint : le `nodeSelector: workload: database` dans le StatefulSet PostgreSQL cible explicitement ces nœuds
- Taint seul = "je refuse les autres", label seul = "je suis ciblable" — les deux ensemble = isolation bidirectionnelle

**Pourquoi pas d'autoscaling :**
- PostgreSQL StatefulSet avec `topologySpreadConstraints maxSkew:1` nécessite un nombre de nœuds prévisible
- L'autoscaling de nœuds DB perturberait la distribution des pods et les PVC (un nouveau nœud n'a pas de PVC)
- Le volume de données est prévisible — pas besoin d'élasticité

---

### 9. Network plugin `azure` (CNI natif)

**Décision** : `network_plugin = "azure"`.

**Comparaison avec kubenet :**

| Critère | kubenet | azure CNI |
|---|---|---|
| IPs des pods | Réseau overlay virtuel | IPs du subnet directement |
| Performance réseau | NAT entre pods et nodes | Pas de NAT, accès direct |
| Nombre d'IPs consommées | Faible (nœuds seulement) | Élevé (nœuds + tous les pods) |
| Compatibilité Azure | Limitée | Native (Load Balancer, NSG...) |
| Complexité | Simple | Nécessite planification CIDR |

**Pourquoi azure CNI :**
- Les pods ont des IPs du subnet `10.4.0.0/22` — directement routables depuis le VNet
- Le NGINX Ingress contacte les pods applicatifs directement par IP sans NAT
- Compatible avec les Network Policies Calico et les Azure Load Balancers

---

### 10. Network policy `calico`

**Décision** : `network_policy = "calico"`.

**Pourquoi :**
- Calico est le moteur de NetworkPolicy le plus complet sur AKS
- Permet de définir des règles d'isolation réseau entre pods et namespaces (ex : namespace `dev` ne peut pas accéder au namespace `ingress-nginx` sauf sur port 80)
- Alternative `azure` (Azure Network Policy Manager) : plus simple mais moins de fonctionnalités

---

### 11. Service CIDR `172.16.0.0/16`

**Décision** : les Services Kubernetes utilisent le range `172.16.0.0/16`, DNS interne sur `172.16.0.10`.

**Pourquoi ce range :**
- Séparé des IPs des pods (`10.4.0.0/22`) et du VNet Hub (`10.0.0.0/16`) et des Spokes (`10.1-3.0.0/16`)
- `172.16.0.0/16` n'est pas utilisé ailleurs dans le plan d'adressage — pas de collision
- DNS (`172.16.0.10`) est dans ce range — CoreDNS écoute sur cette IP

---

## Flux de provisionnement Terraform

```
terraform apply -target=module.aks

  main.tf (modules/aks)
    ├── azurerm_resource_group.aks
    │     → rg-formation-ecom-aks (francecentral)
    │
    ├── azurerm_virtual_network.aks
    │     → vnet-formation-ecom-aks (10.4.0.0/16)
    │
    └── azurerm_subnet.aks
          → subnet-aks (10.4.0.0/22)

  cluster.tf
    └── azurerm_kubernetes_cluster.aks
          → aks-formation-ecom
          → identity SystemAssigned créée
          → default_node_pool "system" (1 nœud, only_critical_addons)
          → network_profile azure CNI + calico + 172.16.0.0/16

  nodepools.tf
    ├── azurerm_kubernetes_cluster_node_pool.apps
    │     → 3 nœuds (autoscaling 3-6, Standard_B2s_v2)
    │
    └── azurerm_kubernetes_cluster_node_pool.db
          → 2 nœuds (fixe, Standard_B2s_v2)
          → taint workload=database:NoSchedule
          → label workload=database

  outputs.tf
    └── kubeconfig (sensitive)
          → az aks get-credentials ou terraform output kubeconfig
```

---

## Limites connues

| Limite | Description | Solution future |
|---|---|---|
| Cluster public | API server exposé sur Internet | `api_server_authorized_ip_ranges` ou `private_cluster_enabled = true` + VPN |
| Pas de monitoring | Pas de Log Analytics workspace | Activer `oms_agent` + Log Analytics |
| Pas d'Azure Policy | Pas de contraintes de gouvernance sur le cluster | Azure Policy add-on pour AKS |
| `Standard_B2s_v2` pour tous les pools | Gabarit identique pour système, apps et DB | Adapter `db_vm_size` à `Standard_D2s_v3` pour PostgreSQL en prod |
| kubeconfig en output Terraform | Accessible à quiconque a accès au state | Utiliser Azure RBAC pour AKS + `az aks get-credentials` |
