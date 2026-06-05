# Module `modules/platform/` — Documentation complète NGINX Ingress

---

## 1. Structure des fichiers Terraform

```
modules/platform/
  ├── providers.tf   → Helm provider + contrainte de version
  ├── variables.tf   → Paramètre kubeconfig_path
  ├── ingress.tf     → helm_release nginx ingress controller
  └── (outputs.tf)   → à créer si l'IP publique doit être exposée
```

---

### `providers.tf`

```hcl
terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}
```

| Élément | Valeur | Rôle |
|---|---|---|
| `source` | `hashicorp/helm` | Provider officiel HashiCorp pour Helm |
| `version = "~> 2.0"` | Compatible 2.x | Verrouille la version majeure — évite les breaking changes de Helm 3 |

**Comment le provider Helm se connecte au cluster :** il lit le fichier kubeconfig pointé par `kubeconfig_path` (défaut `~/.kube/config`). Ce fichier est produit par `az aks get-credentials` ou `terraform output -raw kubeconfig > ~/.kube/config`.

---

### `variables.tf`

```hcl
variable "kubeconfig_path" {
  description = "Chemin vers le fichier kubeconfig"
  type        = string
  default     = "~/.kube/config"
}
```

| Variable | Usage | Note |
|---|---|---|
| `kubeconfig_path` | Passé au provider Helm pour localiser le cluster | Le `~` est résolu par le provider Helm (pas par Terraform lui-même) |

---

### `ingress.tf` — Décorticage ligne par ligne

```hcl
resource "helm_release" "nginx_ingress" {
  name             = "ingress-nginx"          # (1) Nom de la release Helm
  repository       = "https://kubernetes.github.io/ingress-nginx"  # (2) Chart repository
  chart            = "ingress-nginx"          # (3) Nom du chart
  namespace        = "ingress-nginx"          # (4) Namespace cible
  create_namespace = true                     # (5) Crée le namespace si absent

  set {
    name  = "controller.replicaCount"         # (6) Nombre de réplicas du controller
    value = "2"
  }

  set {
    name  = "controller.service.type"         # (7) Type du Service Kubernetes
    value = "LoadBalancer"
  }

  set {
    name  = "controller.nodeSelector.kubernetes\\.io/os"  # (8) Selector OS
    value = "linux"
  }
}
```

| N° | Paramètre | Valeur | Pourquoi |
|---|---|---|---|
| (1) | `name` | `ingress-nginx` | Identifiant de la release — `helm list` l'affiche sous ce nom |
| (2) | `repository` | `kubernetes.github.io/ingress-nginx` | Chart officiel communauté Kubernetes (pas ingress-nginx.io) |
| (3) | `chart` | `ingress-nginx` | Chart qui déploie le controller + ClusterRole + IngressClass |
| (4) | `namespace` | `ingress-nginx` | Namespace dédié — isolé de `dev` et `kube-system` |
| (5) | `create_namespace = true` | Automatique | Évite un manifest séparé pour le namespace |
| (6) | `replicaCount = 2` | 2 pods | HA minimale — si un pod crash, l'autre continue |
| (7) | `service.type = LoadBalancer` | Azure LB | AKS Cloud Controller Manager provisionne automatiquement un Standard Load Balancer Azure avec IP publique |
| (8) | `nodeSelector linux` | linux | Interdit le scheduling sur des nœuds Windows hypothétiques — NGINX est Linux-only |

**Paramètre `kubernetes\\.io/os` :** le double backslash est nécessaire car Terraform échappe le `.` dans les noms de paramètres Helm (`set.name` est un chemin YAML). Sans escape, Terraform interprète `.io/os` comme une sous-clé YAML.

---

## 2. Flux de trafic complet : Internet → Container

```
[1] Client HTTP
    curl http://20.x.x.x/api/orders

[2] DNS resolution
    → Résout 20.x.x.x (IP publique Azure Load Balancer)
    → Pas de DNS ici — accès direct par IP

[3] Azure Standard Load Balancer
    → Reçoit le paquet TCP port 80
    → Backend pool = les 2 VMs portant les pods NGINX Controller
    → Choisit un nœud via round-robin (Azure LB algorithm)
    → Forward vers NodePort du Service ingress-nginx

[4] Service Kubernetes type LoadBalancer (namespace ingress-nginx)
    → Sélecte les pods : app.kubernetes.io/name=ingress-nginx
    → Distribue entre les 2 pods NGINX Controller
    → ClusterIP 172.16.x.x (Service IP interne)

[5] Pod NGINX Controller (node pool apps)
    → Reçoit la requête HTTP
    → Lit le header Host et le path (/api/orders)
    → Cherche dans nginx.conf la règle Ingress correspondante
    → Trouve : Ingress "orders-ingress" namespace dev
               path /api/orders → Service orders-svc port 80

[6] Service ClusterIP "orders-svc" (namespace dev)
    → Sélecte les pods : app=orders
    → Retourne la liste des endpoints (IPs pods)

[7] Pod applicatif (namespace dev, pool apps)
    → IP 10.4.0.x (Azure CNI — IP du subnet directement)
    → NGINX contacte 10.4.0.x:8080 directement (pas de NAT)
    → Le pod traite la requête et renvoie la réponse

[8] Retour
    → Pod → NGINX Controller → Service LB → Azure LB → Client
```

**Détail Azure CNI sur le step [7] :**
Avec Azure CNI, l'IP du pod (`10.4.0.x`) est directement routable depuis le VNet. NGINX lit les endpoints du Service et contacte l'IP du pod sans passer par kube-proxy. Cela réduit la latence (pas de NAT) et permet des features NGINX avancées comme le keepalive vers les upstreams.

**Comparaison avec kubenet :**
Avec kubenet, les pods ont des IPs virtuelles (overlay). NGINX doit passer par kube-proxy qui fait la translation NAT. Latence supplémentaire ~1-2ms.

---

## 3. Ce que le chart `ingress-nginx` déploie réellement

```bash
helm template ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx | grep "^kind:" | sort | uniq -c
```

Le chart crée :
| Ressource K8s | Quantité | Rôle |
|---|---|---|
| `Deployment` | 1 | Controller NGINX (2 réplicas) |
| `Service` (LoadBalancer) | 1 | Point d'entrée externe |
| `Service` (ClusterIP) | 1 | Metrics/health internes |
| `IngressClass` | 1 | `nginx` — classe par défaut |
| `ClusterRole` | 1 | Droits lecture sur Ingress, Services, Endpoints (tous ns) |
| `ClusterRoleBinding` | 1 | Lie le ClusterRole au ServiceAccount |
| `ServiceAccount` | 1 | Identité du controller |
| `ConfigMap` | 1 | Configuration nginx globale (timeouts, logs…) |
| `ValidatingWebhookConfiguration` | 1 | Valide les ressources Ingress à l'admission |

---

## 4. Décisions ADR — rappel des choix clés

### Pourquoi Helm provider Terraform plutôt que `kubectl apply` ?

| Approche | Avantage | Inconvénient |
|---|---|---|
| `helm_release` Terraform (retenu) | Versionnable, idempotent, même état que l'infra | Nécessite le provider Helm configuré |
| `kubectl apply -f` manuel | Simple, direct | Non géré par Terraform — état diverge |
| `helm install` en CLI | Contrôle direct | Non reproductible, pas de state Terraform |
| ArgoCD / FluxCD | GitOps complet | Hors périmètre formation |

### Pourquoi `replicaCount: 2` et non 3 ?

- 2 pods = HA minimale : si un pod crash, le Load Balancer Azure bascule sur l'autre en ~10s
- 3 pods = HA robuste (perte de 2 pods tolérée) mais coût supplémentaire
- Les 2 pods se répartissent sur des nœuds différents du pool `apps` naturellement (Kubernetes scheduler)
- Ajouter `podAntiAffinity` dans les Helm values garantirait 1 pod par nœud

### Pourquoi ne pas configurer de `podAntiAffinity` actuellement ?

Limite connue : sans `podAntiAffinity`, les 2 pods peuvent atterrir sur le même nœud. Si ce nœud est evincé, les 2 pods disparaissent simultanément. En formation, ce risque est acceptable.

Pour corriger :
```hcl
set {
  name  = "controller.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution[0].topologyKey"
  value = "kubernetes.io/hostname"
}
```

---

## 5. Propositions d'optimisation

### 5.1 IP publique statique (évite le changement d'IP au redéploiement)

```hcl
# Créer une IP statique Azure
resource "azurerm_public_ip" "ingress" {
  name                = "pip-ingress-${var.team_name}-${var.project_name}"
  resource_group_name = azurerm_resource_group.aks.name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Passer l'IP au chart Helm
set {
  name  = "controller.service.loadBalancerIP"
  value = azurerm_public_ip.ingress.ip_address
}
```

**Pourquoi :** actuellement, Azure assigne une IP dynamique lors de la création du Service LoadBalancer. Si le Service est supprimé et recréé (redéploiement Terraform), l'IP change. Une IP statique permet de configurer les DNS en avance.

---

### 5.2 TLS avec cert-manager

```bash
# Installer cert-manager
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true

# ClusterIssuer Let's Encrypt
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ops@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: nginx
EOF
```

Ensuite, annoter les ressources Ingress :
```yaml
annotations:
  cert-manager.io/cluster-issuer: "letsencrypt-prod"
```

---

### 5.3 Rate limiting et protection DDoS basique

```yaml
# Annotations sur la ressource Ingress
nginx.ingress.kubernetes.io/limit-rps: "100"
nginx.ingress.kubernetes.io/limit-connections: "50"
nginx.ingress.kubernetes.io/limit-rpm: "1000"
```

---

### 5.4 Exposer l'IP publique en output Terraform

```hcl
# modules/platform/outputs.tf — à créer
output "ingress_ip" {
  description = "IP publique du Load Balancer NGINX Ingress"
  value       = data.kubernetes_service.nginx_ingress.status[0].load_balancer[0].ingress[0].ip
}
```

---

### 5.5 Ajouter une version fixe du chart

```hcl
resource "helm_release" "nginx_ingress" {
  # ...
  version = "4.10.1"  # Pin la version — évite les breaking changes lors de terraform apply
}
```

**Pourquoi pin :** sans `version`, `terraform apply` installe toujours la dernière version du chart. Une mise à jour majeure peut changer le comportement du controller sans avertissement.