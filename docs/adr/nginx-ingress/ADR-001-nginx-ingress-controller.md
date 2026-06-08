# ADR-001 — NGINX Ingress Controller sur AKS

| Champ    | Valeur                                         |
|----------|------------------------------------------------|
| Statut   | Accepté                                        |
| Date     | 2026-05-30                                     |
| Auteur   | elGiordano                                     |
| Contexte | Phase 04 — Ingress Controller AKS via Terraform Helm |

---

## Contexte

Le cluster AKS `aks-formation-ecom` héberge des workloads dans le namespace `dev`. Ces workloads doivent être accessibles depuis Internet via des règles de routage HTTP/HTTPS centralisées. Le cluster utilise :

- Network plugin : `azure` (CNI) — les pods ont des IPs du subnet `10.4.0.0/22`
- Network policy : `calico`
- Node pool `system` : `only_critical_addons_enabled = true` — n'accepte que les pods système Kubernetes
- Node pool `apps` : 3-6 nœuds autoscalés, reçoit les workloads applicatifs
- Node pool `db` : 2 nœuds taintés `workload=database:NoSchedule` — réservé à PostgreSQL

Sans Ingress Controller, exposer un service nécessite un LoadBalancer Azure par service, ce qui est coûteux et non scalable.

---

## Décisions et justifications

---

### 1. NGINX Ingress Controller plutôt que les alternatives Azure

**Décision** : déployer `ingress-nginx` (chart officiel de la communauté Kubernetes).

**Alternatives considérées :**

| Option | Description | Raison du rejet |
|---|---|---|
| **ingress-nginx** ✅ | Chart communauté, open source | Retenu |
| AKS HTTP Application Routing | Add-on AKS géré par Microsoft | Déprécié depuis AKS 1.28, remplacé par AGIC |
| AGIC (Application Gateway Ingress Controller) | Azure Application Gateway + add-on AKS | Coût élevé (Application Gateway ~150€/mois), hors budget formation |
| Traefik | Ingress Controller alternatif | Plus complexe à configurer, moins documenté pour AKS |

**Pourquoi ingress-nginx :**
- Un seul Azure Load Balancer pour tous les services exposés
- Chart officiel maintenu par la communauté Kubernetes (`kubernetes.github.io/ingress-nginx`)
- Référence de facto pour la formation Kubernetes
- `IngressClass` `nginx` automatiquement créée et définie comme default

---

### 2. Déploiement via Terraform Helm provider

**Décision** : `helm_release` dans `modules/platform/ingress.tf`.

**Pourquoi :**
- Cohérence : toute l'infrastructure est gérée par Terraform
- `create_namespace = true` : le namespace `ingress-nginx` est créé automatiquement sans manifest séparé
- Idempotent : `terraform apply` ne recrée pas le chart si rien n'a changé
- Versionnable : les paramètres (`replicaCount`, `service.type`) sont dans le code IaC

---

### 3. Service type `LoadBalancer`

**Décision** : `controller.service.type = LoadBalancer`.

**Pourquoi :**

```
Internet
  │
  ▼
Azure Load Balancer Standard  (IP publique provisionnée automatiquement par AKS)
  │
  ▼
Service LoadBalancer ingress-nginx  (kubernetes, namespace ingress-nginx)
  │  sélectionne les pods controller via label app.kubernetes.io/name: ingress-nginx
  ▼
NGINX Controller Pod(s)
  │  lit les ressources Ingress → construit nginx.conf
  ▼
Service ClusterIP de l'application (namespace dev)
  │
  ▼
Pod applicatif
```

- Azure provisionne automatiquement un Standard Load Balancer avec une IP publique statique
- Un seul Load Balancer pour tous les Ingress du cluster (économique)
- L'IP publique est stable — elle ne change pas au redémarrage des pods

**Alternative rejetée** : `NodePort` nécessite d'exposer un port sur chaque nœud et de gérer un Load Balancer externe manuellement.

---

### 4. `replicaCount: 2`

**Décision** : 2 réplicas du controller.

**Pourquoi :**
- Haute disponibilité : si un pod controller crash ou si son nœud est evincé, l'autre pod continue de servir le trafic
- Le Load Balancer Azure distribue le trafic entre les 2 pods via le Service Kubernetes
- 2 est le minimum pour la HA sans coût excessif (versus 3 pour une HA plus robuste)

**Distribution sur les nœuds :**
Les 2 replicas du controller sont schedulés sur le node pool `apps` (le pool `system` refuse les workloads non-système via `only_critical_addons_enabled = true`, le pool `db` est tainté). Kubernetes les répartit sur des nœuds différents si possible.

---

### 5. `nodeSelector: kubernetes.io/os: linux`

**Décision** : restreindre le scheduling aux nœuds Linux.

**Pourquoi :**
- Le cluster pourrait à terme inclure des nœuds Windows (pour des workloads .NET spécifiques)
- NGINX ne tourne que sur Linux — sans ce selector, le pod pourrait être schedulé sur un nœud Windows et échouer
- `kubernetes.io/os: linux` est un label automatiquement posé par Kubernetes sur tous les nœuds Linux

**Pas de `nodeSelector` sur le node pool `apps` :**
Le pool `apps` n'a pas de taint — les pods sans toleration spécifique y atterrissent naturellement. Un `nodeSelector` explicite n'est pas nécessaire.

---

### 6. Namespace dédié `ingress-nginx`

**Décision** : déployer dans le namespace `ingress-nginx` (distinct de `dev`).

**Pourquoi :**
- Isolation des ressources : les RBAC, ServiceAccounts et ConfigMaps du controller ne polluent pas les namespaces applicatifs
- Le controller surveille les Ingress dans **tous** les namespaces — il n'a pas besoin d'être dans le même namespace que les applications
- Pattern standard Kubernetes : les composants d'infrastructure ont leur propre namespace

---

### 7. Azure CNI et impact sur le routage

**Décision** : le cluster utilise `network_plugin = "azure"` (CNI natif Azure).

**Impact sur l'Ingress :**

Avec Azure CNI, chaque pod reçoit une IP directement dans le subnet `10.4.0.0/22`. Le NGINX Controller contacte les pods applicatifs **directement par leur IP**, sans NAT :

```
NGINX Controller (10.4.0.x)
  └── upstream backend: 10.4.0.y:8080  (IP du pod directement)
```

Avec kubenet (réseau overlay), les pods ont des IPs virtuelles — NGINX aurait dû passer par les Services. Avec Azure CNI, NGINX peut bypasser le kube-proxy et contacter les pods directement, ce qui réduit la latence.

---

### 8. Pas de TLS configuré (scope formation)

**Décision** : pas de `cert-manager`, pas de certificats TLS dans ce déploiement.

**Pourquoi :**
- Hors périmètre de l'US Ingress Controller
- La production nécessiterait `cert-manager` + Let's Encrypt ou Azure Key Vault

---

## Flux complet : d'une requête HTTP à un pod applicatif

```
t=0  terraform apply
       helm_release ingress-nginx créé dans namespace ingress-nginx
       Azure provisionne un Standard Load Balancer avec IP publique
       2 pods NGINX Controller démarrent sur le node pool apps
       IngressClass "nginx" créée et définie comme default

t=1  kubectl apply -f mon-ingress.yaml (namespace dev)
       NGINX Controller détecte la nouvelle ressource Ingress via Watch API
       Recompile nginx.conf avec les nouvelles règles de routage
       Recharge nginx (nginx -s reload) sans coupure de trafic

t=2  Requête HTTP entrante
       DNS → IP publique Azure Load Balancer
       Load Balancer → Service LoadBalancer (port 80)
       Service → l'un des 2 pods NGINX Controller
       NGINX lit Host header + path → trouve la règle Ingress correspondante
       NGINX contacte le Service ClusterIP de l'app (namespace dev)
       Service → pod applicatif
       Réponse remonte le même chemin
```

---

## Limites connues

| Limite | Description | Solution future |
|---|---|---|
| Pas de TLS | HTTP uniquement | `cert-manager` + Let's Encrypt |
| IP publique non fixée en IaC | L'IP est provisionnée par Azure dynamiquement | Créer une IP statique Azure et la référencer dans le Helm values |
| Pas de rate limiting | Pas de protection DDoS basique | Annotations NGINX `nginx.ingress.kubernetes.io/limit-rps` |
| `replicaCount: 2` sans podAntiAffinity | Les 2 replicas peuvent atterrir sur le même nœud | Ajouter `podAntiAffinity` dans les Helm values |