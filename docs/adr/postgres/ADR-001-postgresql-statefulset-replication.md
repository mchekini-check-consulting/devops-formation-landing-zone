# ADR-001 — PostgreSQL en cluster répliqué via StatefulSet manuel

| Champ    | Valeur                                      |
|----------|---------------------------------------------|
| Statut   | Accepté                                     |
| Date     | 2026-05-30                                  |
| Auteur   | elGiordano                                  |
| Contexte | Phase 04 — US PostgreSQL StatefulSet manuel |

---

## Contexte

Le cluster AKS héberge un node pool `db` dédié aux workloads de base de données :
- 2 nœuds (`db_node_count = 2`)
- Taint `workload=database:NoSchedule`
- Label `workload=database`
- VM size `Standard_B2s_v2`

L'objectif est de déployer PostgreSQL 16 en cluster répliqué **sans opérateur** (pas de CloudNativePG, pas de Zalando operator) afin de comprendre les mécaniques StatefulSet, streaming replication et stockage persistant.

---

## Décisions et justifications

---

### 1. StatefulSet plutôt que Deployment

**Décision** : utiliser un `StatefulSet` avec `replicas: 3`.

**Pourquoi** :
- Chaque pod reçoit un nom stable et ordonné : `postgres-0`, `postgres-1`, `postgres-2`
- Le nom stable permet de cibler `postgres-0` comme primary de façon déterministe
- Les pods sont créés dans l'ordre (0 → 1 → 2), garantissant que le primary est prêt avant que les replicas tentent de s'y connecter
- Chaque pod reçoit son propre PVC via `volumeClaimTemplates` — un Deployment partagerait le même volume entre tous les pods, incompatible avec PostgreSQL

**Alternatives rejetées** :
- Deployment : pas de noms stables, pas de PVC par pod
- Opérateur (CloudNativePG) : masque les mécaniques sous-jacentes, hors périmètre de la formation

---

### 2. Identification du primary par ordinal

**Décision** : `postgres-0` est toujours le primary. L'init container lit `$(hostname)` pour déterminer le rôle.

**Pourquoi** :
- Le StatefulSet garantit que `postgres-0` existe toujours en premier
- Le label `statefulset.kubernetes.io/pod-name: postgres-0` est posé automatiquement par Kubernetes, ce qui permet de cibler le primary sans script additionnel de labeling
- Pas besoin d'élection de leader (Raft, etcd) pour ce cas d'usage de formation

**Limite** :
- Si `postgres-0` tombe et qu'un replica doit être promu, la promotion est manuelle. Ce cluster ne gère pas le failover automatique (hors périmètre de l'US).

---

### 3. Réplication via `pg_basebackup -R` dans un init container

**Décision** : utiliser un init container (`init-replica`) qui exécute `pg_basebackup -R` pour cloner le primary avant le démarrage du main container.

**Pourquoi** :
- L'init container s'exécute **avant** le main container, garantissant que PGDATA est prêt avant que postgres démarre
- `pg_basebackup -R` est la méthode officielle PostgreSQL pour initialiser un standby :
  - `-Xs` : stream les WAL pendant la copie, garantit la cohérence sans interruption du primary
  - `-R` : écrit automatiquement `standby.signal` et `primary_conninfo` dans `postgresql.auto.conf`
- Pas de `recovery.conf` (supprimé depuis PostgreSQL 12)

**Alternatives rejetées** :
- Script dans le main container : nécessite de gérer le démarrage en deux temps, plus complexe
- `pg_rewind` : utile pour re-synchroniser un replica qui a divergé, pas pour l'init initiale

---

### 4. `docker-entrypoint.sh` comme entrypoint unifié

**Décision** : pas de `command` custom dans le main container, uniquement des `args`. L'image `postgres:16` utilise `docker-entrypoint.sh` comme ENTRYPOINT natif.

**Pourquoi** :
- `docker-entrypoint.sh` détecte si PGDATA est vide ou rempli et adapte son comportement :
  - PGDATA vide (`postgres-0`) : lance `initdb`, exécute `/docker-entrypoint-initdb.d/`, démarre postgres
  - PGDATA rempli (replicas) : skip initdb, skip les scripts d'init, démarre postgres directement
- Gère le drop de privilèges via `gosu postgres` — postgres ne peut pas tourner en root
- Un script custom `exec postgres` (sans gosu) aurait échoué avec `"root" execution is not permitted`

---

### 5. Création du user `replicator` via `/docker-entrypoint-initdb.d/`

**Décision** : monter `init-users.sh` dans `/docker-entrypoint-initdb.d/` via `subPath`.

**Pourquoi** :
- `docker-entrypoint.sh` exécute automatiquement les scripts de ce répertoire après `initdb`, uniquement si PGDATA était vide (donc uniquement sur `postgres-0`)
- Le mot de passe est injecté depuis le Secret Kubernetes via `${REPLICATION_PASSWORD}` — pas de valeur en dur dans le ConfigMap
- `-v ON_ERROR_STOP=1` : si le CREATE USER échoue, psql retourne un code d'erreur non nul → `set -e` arrête le script → le pod échoue proprement plutôt que de continuer sans le user replicator

---

### 6. StorageClass Azure Disk Standard SSD LRS

**Décision** : StorageClass custom `postgres-standard-ssd` avec `skuName: StandardSSD_LRS`.

**Pourquoi** :
- `StandardSSD_LRS` est le meilleur rapport cohérence/coût pour une base de données de formation : plus fiable que `Standard_LRS` (HDD), moins cher que `Premium_LRS`
- `reclaimPolicy: Retain` : si un PVC est supprimé accidentellement, le disque Azure est conservé — les données survivent
- `volumeBindingMode: WaitForFirstConsumer` : le PV est créé dans la même zone Azure que le pod qui le réclame. Sans ce paramètre, le PV pourrait être créé dans une zone différente du pod, rendant le montage impossible sur AKS multi-zone
- `allowVolumeExpansion: true` : agrandir un PVC sans le recréer

---

### 7. Distribution des pods : `topologySpreadConstraints` avec `maxSkew: 1`

**Décision** : utiliser `topologySpreadConstraints` plutôt que `podAntiAffinity`.

**Pourquoi** :

| Critère | `podAntiAffinity required` | `podAntiAffinity preferred` | `topologySpreadConstraints maxSkew:1` |
|---|---|---|---|
| Distribution garantie | Oui (1/node) | Non (best-effort) | Oui (2+1) |
| Nœuds requis | = replicas (3) | ≥ 1 | ≥ 1 |
| `db_node_count` à modifier | Oui → 3 | Non | Non |
| Lisibilité de l'intention | Implicite | Implicite | Explicite |

Avec 2 nœuds et `maxSkew: 1`, la distribution est mathématiquement garantie à 2+1 :
```
pod 1 → node-db-1:1  node-db-2:0  (skew=1 ✓)
pod 2 → node-db-1:1  node-db-2:1  (skew=0 ✓)  état transitoire
pod 3 → node-db-1:2  node-db-2:1  (skew=1 ✓)  état final stable
```

`whenUnsatisfiable: DoNotSchedule` : si un nœud disparaît et qu'un rescheduling créerait skew > 1, le pod attend plutôt que de se concentrer.

---

### 8. Services : Headless + Primary + Read

**Décision** : trois services distincts.

| Service | Type | Selector | Rôle |
|---|---|---|---|
| `postgres` | ClusterIP None (Headless) | `app: postgres` | DNS stable par pod |
| `postgres-primary` | ClusterIP | `statefulset.kubernetes.io/pod-name: postgres-0` | Writes |
| `postgres-read` | ClusterIP | `app: postgres` | Reads (tous les pods) |

**Pourquoi le Headless** :
Sans `clusterIP: None`, Kubernetes crée une IP virtuelle et load-balance les requêtes entre pods. Pour PostgreSQL, chaque pod doit être adressable individuellement. Le Headless Service crée des enregistrements DNS A distincts :
```
postgres-0.postgres.dev.svc.cluster.local → 10.4.x.x
postgres-1.postgres.dev.svc.cluster.local → 10.4.x.y
postgres-2.postgres.dev.svc.cluster.local → 10.4.x.z
```

**Pourquoi le label `pod-name` pour le primary** :
Le label `statefulset.kubernetes.io/pod-name` est posé automatiquement par Kubernetes sur chaque pod d'un StatefulSet. Pas besoin de script pour labeler `postgres-0` comme primary.

---

### 9. Liveness probe sur l'état du WAL Receiver

**Décision** : `liveness-check.sh` vérifie `pg_stat_wal_receiver` sur les replicas.

**Pourquoi** :
- `pg_isready` seul retourne OK même si le WAL Receiver est crashé (postgres tourne toujours)
- Un replica dont le WAL Receiver est mort ne reçoit plus les changements du primary — il sert des données potentiellement obsolètes sans aucune alerte
- `pg_stat_wal_receiver` expose l'état réel du processus de réplication : `streaming`, `catchup`, ou vide (crashed)
- Sur le primary : `pg_is_in_recovery() = f` → la vérification WAL est skippée (le primary n'a pas de WAL Receiver)

**Cycle de récupération automatique** :
```
WAL Receiver crash → liveness-check.sh exit 1 × 3 (30s)
  → Kubernetes redémarre le pod
    → init container init-replica.sh
      → pg_basebackup depuis le primary
        → réplication rétablie
```

---

### 10. Réplication WAL asynchrone

**Décision** : réplication asynchrone (comportement par défaut de PostgreSQL).

**Pourquoi** :
- Le primary répond `COMMIT OK` sans attendre la confirmation des replicas
- Latence minimale pour le client
- En cas de crash du primary avant que les replicas aient reçu les derniers WAL, une faible quantité de données peut être perdue (RPO > 0)
- Acceptable pour un environnement de formation

**Alternative** : `synchronous_commit = remote_apply` force le primary à attendre que les replicas aient appliqué le WAL avant de répondre au client (RPO = 0) mais augmente la latence d'écriture.

---

## Flux complet : du `kubectl apply` au streaming replication

```
kubectl apply -f k8s/postgres/

  ┌─ 00-storageclass.yaml ─────────────────────────────────────────────┐
  │  StorageClass créée, en attente de PVC                             │
  └────────────────────────────────────────────────────────────────────┘

  ┌─ 01-secret.yaml ───────────────────────────────────────────────────┐
  │  Secret postgres-credentials disponible dans le namespace dev      │
  └────────────────────────────────────────────────────────────────────┘

  ┌─ 02-configmap.yaml ────────────────────────────────────────────────┐
  │  postgresql.conf, pg_hba.conf, init-users.sh,                      │
  │  liveness-check.sh, init-replica.sh disponibles                    │
  └────────────────────────────────────────────────────────────────────┘

  ┌─ 03-services.yaml ─────────────────────────────────────────────────┐
  │  postgres (Headless), postgres-primary, postgres-read créés        │
  └────────────────────────────────────────────────────────────────────┘

  ┌─ 04-statefulset.yaml ──────────────────────────────────────────────┐
  │                                                                     │
  │  t=0  postgres-0 schedulé sur node-db-1                            │
  │       topologySpreadConstraints : skew=1 après pod 1               │
  │       PVC pgdata-postgres-0 créé (20Gi StandardSSD_LRS)            │
  │                                                                     │
  │  t=1  init container init-replica.sh (postgres-0)                  │
  │       hostname = postgres-0 → exit 0 immédiat                      │
  │                                                                     │
  │  t=2  main container postgres-0                                     │
  │       docker-entrypoint.sh :                                        │
  │         PGDATA vide → initdb → crée le cluster                     │
  │         postgres temporaire démarre                                 │
  │         init-users.sh → CREATE USER replicator                     │
  │         postgres temporaire arrêté                                  │
  │         postgres définitif démarre → PRIMARY actif                 │
  │         WAL Sender prêt à accepter des connexions de réplication   │
  │                                                                     │
  │  t=3  postgres-1 schedulé sur node-db-2 (skew=0 transitoire)      │
  │       PVC pgdata-postgres-1 créé                                   │
  │       init container init-replica.sh :                             │
  │         boucle pg_isready → postgres-0 répond                      │
  │         rm -rf PGDATA/*                                             │
  │         pg_basebackup -Xs -R → clone postgres-0                    │
  │           écrit standby.signal                                      │
  │           écrit postgresql.auto.conf (primary_conninfo)            │
  │       main container postgres-1 :                                   │
  │         docker-entrypoint.sh : PGDATA rempli → skip initdb         │
  │         postgres démarre → lit standby.signal → mode STANDBY       │
  │         WAL Receiver ouvre connexion vers postgres-0               │
  │         streaming replication active ←──────────────────────────── │
  │                                                                     │
  │  t=4  postgres-2 idem postgres-1 (skew=1 final : 2+1)             │
  │                                                                     │
  └─────────────────────────────────────────────────────────────────────┘
```

---

## Limites connues

| Limite | Description | Solution future |
|---|---|---|
| Pas de failover automatique | Si postgres-0 tombe, le primary est perdu | Patroni ou CloudNativePG |
| Réplication asynchrone | RPO > 0 en cas de crash du primary | `synchronous_commit = remote_apply` |
| Secret manuel | REPLICATION_PASSWORD en base64 dans le repo | Azure Key Vault + CSI driver |
| `wal_keep_size = 128MB` | Un replica trop en retard doit refaire pg_basebackup | Replication slots ou augmenter la valeur |
