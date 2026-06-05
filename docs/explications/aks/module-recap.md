# Module `modules/aks/` — Tableau récapitulatif

---

## 1. Variables (`variables.tf`)

> **Besoin** : Paramétrer le module de façon flexible pour qu'il puisse être réutilisé par plusieurs équipes et projets sans modifier le code source.
>
> **Utilisation** : Ces variables sont passées lors de l'appel du module depuis le root `main.tf` (`module "aks" { team_name = ... }`). Les valeurs par défaut permettent de déployer un cluster fonctionnel sans avoir à tout renseigner.

| Variable | Type | Default | Description |
|---|---|---|---|
| `team_name` | string | — | Nom de l'équipe, utilisé dans le nommage de toutes les ressources (`rg-{team}-...`) |
| `project_name` | string | — | Nom du projet, utilisé dans le nommage (`...-{project}-aks`) |
| `location` | string | `francecentral` | Région Azure où déployer les ressources |
| `aks_address_space` | string | `10.4.0.0/16` | Plage d'adresses IP du VNet dédié AKS (65 536 IPs) |
| `aks_subnet_cidr` | string | `10.4.0.0/22` | Plage du subnet AKS à l'intérieur du VNet (1 022 IPs utilisables, suffisant pour les pods avec Azure CNI) |
| `system_vm_size` | string | `Standard_B2s_v2` | Taille des VMs du node pool system |
| `apps_vm_size` | string | `Standard_B2s_v2` | Taille des VMs du node pool apps |
| `db_vm_size` | string | `Standard_B2s_v2` | Taille des VMs du node pool db |
| `apps_min_count` | number | `3` | Nombre minimum de nœuds apps quand l'autoscaling réduit la capacité |
| `apps_max_count` | number | `6` | Nombre maximum de nœuds apps quand l'autoscaling augmente la capacité |
| `db_node_count` | number | `2` | Nombre fixe de nœuds db (pas d'autoscaling — les bases de données préfèrent la stabilité) |
| `tags` | map(string) | `{}` | Tags Azure appliqués à toutes les ressources pour le suivi des coûts et l'organisation |

---

## 2. Ressources réseau (`main.tf`)

> **Besoin** : Fournir au cluster AKS un réseau isolé avec une plage d'IPs dédiée, indépendante des VNets hub/spoke existants, pour éviter les conflits d'adressage et cloisonner le trafic Kubernetes.
>
> **Utilisation** : Le VNet et le subnet sont créés en amont du cluster. L'ID du subnet (`azurerm_subnet.aks.id`) est ensuite injecté dans chaque node pool via `vnet_subnet_id`, afin qu'Azure CNI puisse attribuer des IPs du subnet directement aux pods.

| Ressource | Nom généré | Description |
|---|---|---|
| `azurerm_resource_group.aks` | `rg-{team}-{project}-aks` | Resource group dédié au cluster AKS, isole les ressources AKS du reste de l'infra |
| `azurerm_virtual_network.aks` | `vnet-{team}-{project}-aks` | VNet dédié au cluster AKS avec la plage `10.4.0.0/16`, séparé des VNets hub/spoke |
| `azurerm_subnet.aks` | `subnet-aks` | Subnet unique dans lequel les nœuds et pods AKS obtiennent leurs IPs (Azure CNI attribue une IP du subnet à chaque pod) |

---

## 3. Cluster AKS (`cluster.tf`)

> **Besoin** : Provisionner le plan de contrôle Kubernetes managé par Azure (API server, etcd, scheduler) ainsi que le node pool système qui héberge les composants internes du cluster (CoreDNS, kube-proxy, metrics-server…).
>
> **Utilisation** : Ressource centrale du module. Elle crée le cluster AKS et expose son ID (`azurerm_kubernetes_cluster.aks.id`), utilisé par `nodepools.tf` pour y rattacher les pools `apps` et `db`. Elle expose aussi le `kube_config_raw` récupéré dans `outputs.tf` pour permettre l'accès `kubectl`.

| Paramètre | Valeur | Description |
|---|---|---|
| `name` | `aks-{team}-{project}` | Nom du cluster AKS |
| `dns_prefix` | `aks-{team}-{project}` | Préfixe DNS pour l'API server (génère `aks-{team}-{project}.hcp.{region}.azmk8s.io`) |
| `private_cluster_enabled` | `false` | API server accessible publiquement (pas de Private Link), permet `kubectl` depuis l'extérieur |
| `identity.type` | `SystemAssigned` | Azure crée automatiquement une Managed Identity pour le cluster (pas besoin de gérer un Service Principal) |
| `network_profile.network_plugin` | `azure` | Azure CNI — chaque pod reçoit une IP du subnet (pas d'overlay), meilleure performance réseau |
| `network_profile.network_policy` | `calico` | Calico gère les Network Policies Kubernetes pour le filtrage du trafic entre pods |
| `network_profile.service_cidr` | `172.16.0.0/16` | Plage d'IPs virtuelles pour les Services Kubernetes (ClusterIP), ne doit pas chevaucher le VNet |
| `network_profile.dns_service_ip` | `172.16.0.10` | IP du service CoreDNS dans le cluster, doit être dans le `service_cidr` |
| `default_node_pool.name` | `system` | Nom du node pool par défaut, réservé aux composants système |
| `default_node_pool.node_count` | `1` | Un seul nœud — suffisant pour les pods système (CoreDNS, kube-proxy, etc.) |
| `default_node_pool.only_critical_addons_enabled` | `true` | Applique le taint `CriticalAddonsOnly=true:NoSchedule` — seuls les pods système tolèrent ce taint |
| `default_node_pool.temporary_name_for_rotation` | `systemtmp` | Nom temporaire utilisé par Azure lors de la rotation du node pool (obligatoire pour certaines opérations de maintenance) |

---

## 4. Node pools additionnels (`nodepools.tf`)

> **Besoin** : Séparer les workloads applicatifs et les bases de données sur des nœuds dédiés, avec des profils de ressources et des politiques de scheduling différents.
>
> **Utilisation** : Ces deux ressources `azurerm_kubernetes_cluster_node_pool` sont rattachées au cluster via son ID. Les pods sont dirigés vers le bon pool grâce aux taints/tolerations (pool `db`) et aux node labels/selectors (les deux pools).

### Node pool `apps`

> **Besoin** : Offrir une capacité de calcul scalable et redondante pour l'ensemble des workloads métier. Le Cluster Autoscaler surveille les pods en état `Pending` : si un pod ne peut pas être placé faute de ressources, un nouveau nœud est provisionné automatiquement dans la limite de `max_count`.

| Paramètre | Valeur | Description |
|---|---|---|
| `name` | `apps` | Pool dédié aux workloads applicatifs (APIs, frontends, microservices) |
| `vm_size` | via `var.apps_vm_size` | Taille des VMs applicatives |
| `min_count` | `3` | Minimum garanti de nœuds — assure la haute disponibilité |
| `max_count` | `6` | Plafond de scaling — limite les coûts |
| `auto_scaling_enabled` | `true` | Le Cluster Autoscaler ajuste automatiquement le nombre de nœuds selon la charge |
| `vnet_subnet_id` | `subnet-aks` | Même subnet que les autres pools |

### Node pool `db`

> **Besoin** : Réserver des nœuds exclusivement aux workloads stateful (PostgreSQL) qui nécessitent des ressources stables et ne doivent jamais être perturbés par un scale-down ou colocalisés avec des pods applicatifs.
>
> **Utilisation** : Le taint `workload=database:NoSchedule` empêche tout pod non autorisé de s'y placer. Les StatefulSets de bases de données doivent déclarer la tolérance correspondante **et** un `nodeSelector: workload: database`.

| Paramètre | Valeur | Description |
|---|---|---|
| `name` | `db` | Pool dédié aux workloads base de données |
| `vm_size` | via `var.db_vm_size` | Taille des VMs pour les bases de données |
| `node_count` | `2` | Nombre fixe de nœuds — les bases de données nécessitent une capacité prévisible |
| `auto_scaling_enabled` | `false` | Pas d'autoscaling — évite les perturbations sur des workloads stateful |
| `node_taints` | `workload=database:NoSchedule` | Seuls les pods avec la tolérance correspondante peuvent être schedulés ici |
| `node_labels` | `workload=database` | Label utilisé par les `nodeSelector` des pods DB pour cibler ce pool |

---

## 5. Outputs (`outputs.tf`)

> **Besoin** : Rendre accessible le fichier de configuration `kubectl` en dehors du module, pour permettre à d'autres outils (CI/CD, Helm, scripts) de s'authentifier auprès du cluster.
>
> **Utilisation** : La valeur est propagée jusqu'au root `outputs.tf` sous le nom `aks_kubeconfig`. Elle peut être récupérée via `terraform output -raw kubeconfig > ~/.kube/config` pour configurer `kubectl` localement, ou injectée comme secret dans un pipeline CI/CD.

| Output | Sensible | Description |
|---|---|---|
| `kubeconfig` | Oui | Contenu brut du fichier kubeconfig (`kube_config_raw`), permet de se connecter au cluster avec `kubectl`. Marqué `sensitive` car il contient les credentials d'accès au cluster |

---

## 6. Intégration root

> **Besoin** : Instancier le module `aks` depuis le root Terraform en lui passant les paramètres spécifiques au projet.

| Fichier | Ajout | Description |
|---|---|---|
| `main.tf` | `module "aks"` | Appelle le module avec `team_name`, `project_name = "ecom"`, `location` |
| `outputs.tf` | `aks_kubeconfig` | Expose le kubeconfig au niveau root via `terraform output -raw kubeconfig` |
