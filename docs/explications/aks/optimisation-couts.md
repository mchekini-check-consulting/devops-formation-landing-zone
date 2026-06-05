# Module `modules/aks/` — Optimisations de coûts

---

## Vue d'ensemble des coûts actuels

```
Formation — francecentral — Standard_B2s_v2 × 6 nœuds actifs (min)

  node pool system   1 nœud   × ~0,048€/h  =  ~0,048€/h
  node pool apps     3 nœuds  × ~0,048€/h  =  ~0,144€/h
  node pool db       2 nœuds  × ~0,048€/h  =  ~0,096€/h
                                               ──────────
  Total VMs minimum                         =  ~0,288€/h  →  ~207€/mois

  Azure Disk StandardSSD_LRS 2 Gi × 3 PVC   =  ~0,30€/mois (négligeable)
  Load Balancer Standard                    =  ~18€/mois
                                               ──────────
  Total estimé                              =  ~225€/mois
```

> Les VMs burstable `B` sont ~50% moins chères que `D` de même gabarit — choix adapté à la formation.

---

## 1. Réduire le node pool `system` à 0 hors heures

> **Contexte** : le nœud system héberge CoreDNS, kube-proxy, metrics-server. Il tourne même la nuit.

**Optimisation** : coupler `--start-stop-cluster` (Azure CLI) ou des schedules d'arrêt/démarrage cluster.

```bash
# Arrêter le cluster entier (tous les nœuds = 0)
az aks stop \
  --name aks-formation-ecom \
  --resource-group rg-formation-ecom-aks

# Redémarrer
az aks start \
  --name aks-formation-ecom \
  --resource-group rg-formation-ecom-aks
```

**Économie estimée** : arrêt 16h/jour + weekend → ~60% du coût VM économisé ≈ ~125€/mois.

**Risque** : aucun en formation — les PVCs (Azure Disk) sont préservés à l'arrêt.

---

## 2. Réduire `apps_min_count` à 1 en dehors des charges

> **Contexte** : `min_count = 3` maintient 3 nœuds apps même sans workload.

**Optimisation** : modifier `apps_min_count` dans `terraform.tfvars` selon les phases :

```hcl
# terraform.tfvars — hors charge
apps_min_count = 1
apps_max_count = 6
```

```bash
terraform apply -target=module.aks
```

**Économie** : passer de 3 nœuds minimum à 1 économise 2 × ~0,048€/h = ~70€/mois.

**Risque** : perte de HA — si le nœud unique crash, les pods sont down le temps du reschedule (~3-5 min). Acceptable en formation, inacceptable en production.

---

## 3. Utiliser `Standard_B2ls_v2` pour le pool `system`

> **Contexte** : le nœud system n'héberge que des pods légers (CoreDNS 100m CPU, metrics-server 100m CPU).

**Optimisation** : réduire la taille du nœud system.

```hcl
# variables.tf — valeur par défaut à modifier
variable "system_vm_size" {
  default = "Standard_B2ls_v2"  # 2 vCPU, 2 GB RAM — ~0,038€/h
}
```

`Standard_B2ls_v2` : même vCPU que `B2s_v2`, moitié de RAM (2 GB vs 4 GB) — suffisant pour les composants système.

**Économie** : ~10€/mois sur le nœud system.

---

## 4. Spot instances pour le pool `apps`

> **Contexte** : les pods applicatifs peuvent tolérer des interruptions (~2 min de préavis).

**Optimisation** : utiliser des VMs Spot (~60-80% moins chères) pour le pool apps.

```hcl
resource "azurerm_kubernetes_cluster_node_pool" "apps" {
  # ...
  priority        = "Spot"
  eviction_policy = "Delete"
  spot_max_price  = -1  # prix maximum = prix à la demande

  node_labels = {
    "kubernetes.azure.com/scalesetpriority" = "spot"
  }
  node_taints = [
    "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"
  ]
}
```

**Déployer les workloads tolérables sur Spot** :
```yaml
tolerations:
  - key: "kubernetes.azure.com/scalesetpriority"
    operator: "Equal"
    value: "spot"
    effect: "NoSchedule"
```

**Économie** : `Standard_B2s_v2` Spot ≈ 0,014€/h vs 0,048€/h → économie de 70% sur le pool apps ≈ ~50€/mois.

**Risque** : les pods peuvent être expulsés sans préavis si Azure récupère la capacité. Requiert des workloads stateless avec `PodDisruptionBudget`.

---

## 5. Réduire `db_node_count` à 1 en développement

> **Contexte** : 2 nœuds db sont nécessaires pour la HA et `topologySpreadConstraints`. En dev seul, 1 nœud suffit.

**Optimisation** :

```hcl
# terraform.tfvars — environnement dev
db_node_count = 1
```

Avec 1 nœud db, `topologySpreadConstraints maxSkew:1 DoNotSchedule` devient bloquant (impossible de satisfaire la contrainte avec 3 pods sur 1 nœud). Adapter le StatefulSet :

```yaml
# 04-statefulset.yaml — dev uniquement
replicas: 1  # Un seul pod PostgreSQL, pas de réplication
```

**Économie** : 1 nœud db économisé → ~35€/mois.

**Risque** : pas de réplication, pas de HA — PostgreSQL en mode standalone. Acceptable uniquement en dev.

---

## 6. `StandardSSD_LRS` → `Standard_LRS` pour les PVCs non-critiques

> **Contexte** : les PVCs PostgreSQL utilisent `StandardSSD_LRS`. Pour des données temporaires (logs, caches), le HDD standard suffit.

**Optimisation** : créer une StorageClass économique pour les volumes non-critiques.

```hcl
# Ajouter dans k8s/postgres/00-storageclass.yaml
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: standard-hdd
provisioner: disk.csi.azure.com
parameters:
  skuName: Standard_LRS  # HDD managé — ~50% moins cher que SSD
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
```

**Tarifs Azure Disk (francecentral, estimatif)** :
| SKU | Prix/GB/mois |
|---|---|
| `Standard_LRS` (HDD) | ~0,040€ |
| `StandardSSD_LRS` (retenu) | ~0,075€ |
| `Premium_LRS` (SSD NVMe) | ~0,135€ |

**Économie** : 3 PVCs × 2 GB × différentiel ≈ négligeable à cette échelle. L'impact devient significatif sur des volumes de 100+ GB.

---

## 7. Désactiver le pool `db` hors sessions de formation

> **Contexte** : le pool db (2 nœuds) tourne en permanence même quand PostgreSQL n'est pas utilisé.

**Optimisation** : scaler à 0 via Azure CLI (uniquement pour les node pools non-system).

```bash
# Scaler le pool db à 0
az aks nodepool scale \
  --cluster-name aks-formation-ecom \
  --resource-group rg-formation-ecom-aks \
  --name db \
  --node-count 0

# Remettre à 2 avant la session
az aks nodepool scale \
  --cluster-name aks-formation-ecom \
  --resource-group rg-formation-ecom-aks \
  --name db \
  --node-count 2
```

> **Note** : scaler à 0 un node pool non-autoscalé est possible via Azure CLI. Les PVCs (Azure Disk) sont préservés.

**Économie** : 2 nœuds db × 0,048€/h × 16h/jour × 22j/mois ≈ ~34€/mois.

---

## 8. Activer `--uptime-sla` uniquement si SLA requis

> **Contexte** : sans `--uptime-sla`, le plan de contrôle AKS est gratuit mais sans SLA garanti sur l'API server.

| Tier | SLA API server | Prix |
|---|---|---|
| Free (défaut) | Aucun SLA officiel | 0€/mois |
| Standard (Uptime SLA) | 99,9% (zone redondante) | ~73€/mois |
| Premium | 99,95% | ~438€/mois |

**Pour la formation** : le tier Free est suffisant. L'API server AKS est hautement disponible en pratique même sans SLA payant.

```hcl
# cluster.tf — ne pas ajouter sku_tier en formation
# En production seulement :
# sku_tier = "Standard"
```

**Économie** : ne pas activer le Uptime SLA = économie de ~73€/mois.

---

## Matrice de décision par environnement

| Optimisation | Dev/Formation | Staging | Production |
|---|---|---|---|
| Arrêt cluster hors heures | ✅ Recommandé | ✅ Possible | ❌ Interdit |
| `apps_min_count = 1` | ✅ Acceptable | ⚠️ Risqué | ❌ Interdit |
| `Standard_B2ls_v2` system | ✅ OK | ✅ OK | ⚠️ Mesurer |
| Spot instances apps | ✅ Recommandé | ⚠️ Risqué | ⚠️ Seulement workloads stateless |
| `db_node_count = 1` | ✅ Dev seulement | ❌ | ❌ |
| Pool db scalé à 0 hors usage | ✅ Recommandé | ⚠️ | ❌ |
| Uptime SLA désactivé | ✅ | ⚠️ | ❌ — activer Standard |
| `Standard_B2s_v2` pour db | ✅ | ⚠️ | ❌ — `D4s_v3` minimum |