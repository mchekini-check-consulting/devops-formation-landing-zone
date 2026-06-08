# Module `modules/aks/` — Alternatives et comparatifs

---

## 1. Network plugin : `azure` CNI vs `kubenet`

> **Contexte** : choix structurant du réseau AKS — impacte l'adressage, la performance et la compatibilité avec les autres composants Azure.

| Critère | `kubenet` | `azure` CNI (retenu) |
|---|---|---|
| **IPs des pods** | Réseau overlay virtuel (10.244.0.0/16) — NAT vers le VNet | IPs du subnet directement (10.4.0.0/22) — pas de NAT |
| **Consommation IPs VNet** | Faible : 1 IP VNet par nœud | Élevée : 1 IP VNet par pod (nœuds + pods) |
| **Performance réseau** | Pénalité NAT entre pods et nœuds (~5-10% latence) | Accès direct, latence minimale |
| **Routabilité depuis Azure** | Non — pods non accessibles depuis le VNet sans règle | Oui — pods directement accessibles depuis le Hub/Spoke |
| **Network Policies** | Calico ou Azure NPM | Calico ou Azure NPM — même compatibilité |
| **Load Balancer Azure** | Compatible | Compatible natif |
| **Intégration NGINX Ingress** | Passe par kube-proxy (Service → Pod) | Contact direct pod IP (bypass kube-proxy) |
| **Planification CIDR** | Simple — pas de conflit VNet | Requiert planification : pods consomment des IPs du subnet |

**Pourquoi `azure` CNI a été retenu :** avec NGINX Ingress, le controller lit les endpoints des Services et contacte les pods directement par IP. Avec Azure CNI, cette IP est dans le subnet — pas de NAT intermédiaire. Le subnet `/22` (1 024 IPs) est suffisant pour 9 nœuds × ~30 pods max (270 pods) avec large marge.

---

## 2. Network policy : `calico` vs `azure` NPM

> **Contexte** : le moteur de Network Policy détermine les règles d'isolation réseau entre pods.

| Critère | Azure NPM | `calico` (retenu) |
|---|---|---|
| **Type** | Natif Azure (intégré) | Open source (CNCF) |
| **Fonctionnalités NetworkPolicy** | Standard Kubernetes uniquement | Standard Kubernetes + CRD Calico (GlobalNetworkPolicy, HostEndpoint…) |
| **Performance** | eBPF sur certaines versions | iptables ou eBPF selon config |
| **Observabilité** | Limitée | `calicoctl` + `kubectl` + Prometheus metrics |
| **Support Windows nodes** | Oui | Linux uniquement |
| **Complexité opérationnelle** | Faible | Moyenne |
| **Cas d'usage avancé** | Non (pas de GlobalPolicy) | Oui — isolation multi-tenant, egress control |

**Pourquoi Calico :** les namespaces `dev`, `ingress-nginx`, `kube-system` doivent pouvoir être isolés par des Network Policies. Calico est la référence de facto pour la formation et supporte les politiques inter-namespaces que Azure NPM ne couvre pas.

---

## 3. Identité cluster : `SystemAssigned` vs `UserAssigned`

> **Contexte** : le cluster AKS a besoin d'une identité Azure pour provisionner les ressources en son nom (Load Balancer, Azure Disk, IP publiques).

| Critère | `SystemAssigned` (retenu) | `UserAssigned` |
|---|---|---|
| **Création** | Automatique à la création du cluster | Manuelle avant la création du cluster |
| **Gestion du cycle de vie** | Azure — supprimée avec le cluster | Indépendante — survit à la suppression du cluster |
| **Principal ID** | Connu après `terraform apply` seulement | Connu avant création — attribution de rôles possible en amont |
| **Rotation des credentials** | Azure gère automatiquement | Azure gère automatiquement |
| **Portabilité** | Liée au cluster | Réutilisable par plusieurs clusters ou services |
| **Contrôle RBAC préalable** | Non — les rôles sont assignés après création | Oui — pattern IAC strict : rôles assignés avant création |
| **Complexité Terraform** | Faible (`identity { type = "SystemAssigned" }`) | Élevée (`azurerm_user_assigned_identity` + role assignments) |

**Pourquoi `SystemAssigned` :** en contexte formation, la simplicité prime. En production, `UserAssigned` est préférable pour permettre des `azurerm_role_assignment` avant la création du cluster, évitant les race conditions entre la création du cluster et l'attribution des droits.

---

## 4. Visibilité API server : public vs privé

> **Contexte** : l'API server Kubernetes est l'endpoint de contrôle du cluster — son exposition détermine qui peut exécuter `kubectl`.

| Critère | Cluster privé (`private_cluster_enabled = true`) | Cluster public (retenu) |
|---|---|---|
| **Accès API server** | Via adresse IP privée VNet uniquement | Via Internet (FQDN public) |
| **`kubectl` depuis poste dev** | Requiert VPN ou Azure Bastion | Direct — `az aks get-credentials` suffit |
| **Surface d'attaque** | Minimale — API server non accessible depuis Internet | Élevée — API server exposé (protégé par auth Kubernetes) |
| **CI/CD** | Runner doit être dans le VNet ou via Private Endpoint | Runner externe possible |
| **Coût supplémentaire** | Azure Private DNS Zone (~2€/mois) + Private Endpoint | Aucun |
| **Complexité opérationnelle** | Élevée — jump host ou VPN requis | Faible |

**Pourquoi cluster public :** contexte formation — les stagiaires accèdent au cluster depuis leurs postes sans infrastructure réseau supplémentaire. En production, activer `private_cluster_enabled = true` ou restreindre avec `api_server_authorized_ip_ranges = ["<office-ip>/32"]`.

---

## 5. Autoscaling pool `apps` : Cluster Autoscaler vs KEDA vs manuel

> **Contexte** : le pool `apps` héberge les workloads métier dont la charge est variable.

| Critère | Manuel (`node_count` fixe) | **Cluster Autoscaler** (retenu) | KEDA (Kubernetes Event-driven Autoscaling) |
|---|---|---|---|
| **Déclencheur** | Opérateur humain | Pods `Pending` faute de ressources | Métriques externes (queue length, HTTP RPS…) |
| **Granularité** | Nœud | Nœud | Pod (HPA amélioré) |
| **Réactivité** | Nulle | ~2-5 minutes (provisionning VM) | Secondes (scale pod) + minutes (scale nœud) |
| **Coût** | Fixe — sur-provisionnement probable | Optimisé — nœuds ajoutés/retirés selon besoin | Optimisé si combiné avec Cluster Autoscaler |
| **Configuration** | Triviale | Simple (`min_count`, `max_count`) | Élevée — ScaledObject CRD par workload |
| **Cas d'usage** | Charge prévisible et stable | Charge variable imprévisible | Workloads event-driven (messages, jobs) |

**Pourquoi Cluster Autoscaler :** le workload `ecom` a une charge variable typique (pics commandes, soldes). Le Cluster Autoscaler est natif AKS — pas de composant supplémentaire. KEDA sera pertinent si des queues RabbitMQ ou Azure Service Bus sont introduites.

---

## 6. Isolation pool `db` : taint+label vs namespace seul vs node affinity seul

> **Contexte** : les nœuds `db` doivent être exclusivement réservés à PostgreSQL.

| Critère | Namespace seul | Node Affinity seul | **Taint + Label** (retenu) |
|---|---|---|---|
| **Empêche les autres pods** | Non — un pod dans `dev` peut aller sur `db` | Non — `nodeAffinity required` attire mais n'interdit pas | Oui — `NoSchedule` bloque tout pod sans tolération |
| **Cible explicitement les nœuds** | Non | Oui (`requiredDuringScheduling`) | Oui (`nodeSelector`) |
| **Isolation bidirectionnelle** | Non | Partielle | Oui — taint rejette + label cible |
| **Overhead opérationnel** | Faible | Moyen | Moyen |
| **Mise en œuvre Terraform** | N/A | `node_taints` seul possible | `node_taints` + `node_labels` |

**Pourquoi taint + label :** le taint `workload=database:NoSchedule` garantit qu'aucun pod sans tolérance ne s'y schedule — même un pod oublié dans `dev` sans `nodeSelector`. Le label `workload=database` complète avec un ciblage explicite. Les deux ensemble forment une isolation bidirectionnelle robuste.

---

## 7. Taille VMs : `Standard_B2s_v2` vs alternatives

> **Contexte** : toutes les VMs du cluster utilisent `Standard_B2s_v2` (2 vCPU, 4 GB RAM).

| VM Size | vCPU | RAM | Prix/h (est.) | Usage approprié |
|---|---|---|---|---|
| `Standard_B2s_v2` (retenu) | 2 | 4 GB | ~0,048€ | Formation — burstable, économique |
| `Standard_D2s_v3` | 2 | 8 GB | ~0,095€ | Production générale — RAM 2× |
| `Standard_D4s_v3` | 4 | 16 GB | ~0,190€ | PostgreSQL production — plus de RAM pour shared_buffers |
| `Standard_E2s_v3` | 2 | 16 GB | ~0,126€ | Workloads memory-intensive (Redis, Elasticsearch) |
| `Standard_F2s_v2` | 2 | 4 GB | ~0,085€ | CPU-bound (build, calcul) |

**Limite `Standard_B2s_v2` :** les VMs burstable (`B`) accumulent des crédits CPU au repos et les dépensent en charge. En soutenu, les performances chutent. Pour un PostgreSQL en production :
- Minimum : `Standard_D2s_v3` (8 GB RAM → `shared_buffers = 2GB`)
- Recommandé : `Standard_D4s_v3` ou `Standard_E2s_v3` (16 GB RAM → `shared_buffers = 4GB`)

---

## 8. Architecture réseau AKS : VNet dédié vs Spoke existant vs Hub injection

> **Contexte** : le cluster AKS a son propre VNet `10.4.0.0/16` séparé de l'architecture Hub/Spoke.

| Architecture | Description | Avantages | Inconvénients |
|---|---|---|---|
| **VNet dédié** (retenu) | AKS dans son propre VNet `10.4.0.0/16` | Isolation totale, pas de conflit CIDR, déployable indépendamment | Peering requis pour accéder aux services Hub (APIM, Keycloak) |
| **Subnet dans Spoke existant** | AKS partage le VNet `10.2.0.0/16` (spoke-ecom) | Un seul VNet, moins de peerings | Consommation IPs élevée (Azure CNI) dans le Spoke, couplage fort |
| **Injection Hub** | AKS dans le VNet Hub `10.0.0.0/16` | Accès direct à tous les services partagés | Hub pollué par les pods AKS, violation du principe d'isolation Hub |

**Pourquoi VNet dédié :** le subnet `/22` pour Azure CNI consomme potentiellement 1 024 IPs — injecter ça dans un Spoke ou le Hub perturberait tout le plan d'adressage. Le peering vers le Hub est prévu (`10.4.0.0/16 ↔ 10.0.0.0/16`) quand les workloads AKS auront besoin de Keycloak ou d'APIM.
