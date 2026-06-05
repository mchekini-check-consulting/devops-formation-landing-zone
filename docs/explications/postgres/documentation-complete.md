# PostgreSQL StatefulSet — Documentation complète

---

## 1. Détail des manifests

### `00-storageclass.yaml` — StorageClass Azure Disk

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: postgres-standard-ssd
provisioner: disk.csi.azure.com       # (1)
parameters:
  skuName: StandardSSD_LRS            # (2)
volumeBindingMode: WaitForFirstConsumer  # (3)
reclaimPolicy: Retain                 # (4)
allowVolumeExpansion: true            # (5)
```

| N° | Paramètre | Valeur | Pourquoi |
|---|---|---|---|
| (1) | `provisioner` | `disk.csi.azure.com` | Driver CSI natif AKS pour Azure Disk — remplace l'ancien in-tree `kubernetes.io/azure-disk` |
| (2) | `skuName` | `StandardSSD_LRS` | SSD managé LRS (Locally Redundant Storage) — meilleur IOPS que HDD, moins cher que Premium SSD |
| (3) | `volumeBindingMode` | `WaitForFirstConsumer` | Le PV est provisionné dans la même zone AZ que le pod qui le consomme — évite les erreurs "volume not available in zone" |
| (4) | `reclaimPolicy` | `Retain` | Le PV **n'est pas supprimé** quand le PVC est supprimé — protection des données PostgreSQL en cas de `kubectl delete pvc` accidentel |
| (5) | `allowVolumeExpansion` | `true` | Permet d'augmenter la taille du PVC sans recréer le volume (`kubectl edit pvc pgdata-postgres-0` puis modifier `storage`) |

---

### `01-secret.yaml` — Credentials PostgreSQL

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: postgres-credentials
  namespace: dev
type: Opaque
data:
  POSTGRES_PASSWORD: YWRtaW4xMjM=      # base64("admin123")
  REPLICATION_PASSWORD: YWRtaW4xMjM=  # base64("admin123")
```

| Clé | Consommateur | Usage |
|---|---|---|
| `POSTGRES_PASSWORD` | Container `postgres` (main) | Mot de passe du superuser `postgres` — défini via `POSTGRES_PASSWORD` env de l'image officielle |
| `REPLICATION_PASSWORD` | Init container + container main | Mot de passe du user `replicator` — utilisé par `pg_basebackup -U replicator` et `init-users.sh` |

**Pourquoi deux mots de passe séparés :** le user `replicator` a uniquement le privilege `REPLICATION` — pas d'accès aux données. Séparer les credentials limite l'impact si le mot de passe de réplication est compromis.

**Limitation formation :** les deux mots de passe sont identiques (`admin123`) et encodés en base64 (pas chiffrés). En production, utiliser Azure Key Vault + External Secrets Operator.

---

### `02-configmap.yaml` — Configuration PostgreSQL et scripts

Le ConfigMap contient 5 entrées réparties en deux catégories :

#### Fichiers de configuration PostgreSQL

**`postgresql.conf`** — paramètres du serveur PostgreSQL :

| Paramètre | Valeur | Pourquoi |
|---|---|---|
| `wal_level = replica` | Minimum pour la réplication | Active l'écriture des WAL nécessaires aux standbys |
| `max_wal_senders = 10` | 10 connexions WAL sender | Permet jusqu'à 10 replicas (3 ici) + marge pour `pg_basebackup` |
| `wal_keep_size = 128MB` | 128 MB de WAL retenus | Si un replica décroche, le primaire garde 128 MB de WAL pour permettre la resynchronisation sans `pg_basebackup` |
| `hot_standby = on` | Replicas acceptent les lectures | Les replicas répondent aux SELECT pendant la réplication |
| `hot_standby_feedback = on` | Feedback réplica → primaire | Le réplica informe le primaire des transactions actives — évite que le primaire supprime des tuples dont le réplica a encore besoin (vacuum conflicts) |
| `listen_addresses = '*'` | Écoute sur toutes les interfaces | Nécessaire pour que les autres pods puissent se connecter via l'IP du pod |
| `max_connections = 100` | 100 connexions simultanées | Suffisant pour la formation. En prod, utiliser PgBouncer |

**`pg_hba.conf`** — authentification PostgreSQL (Host-Based Authentication) :

```
local   all        all                  trust     # Connexions locales (unix socket) sans mdp
host    all        all  127.0.0.1/32    trust     # Loopback IPv4
host    all        all  ::1/128         trust     # Loopback IPv6
host    all        all  10.4.0.0/22     md5       # Réseau Azure CNI → authentification par mdp
host    replication replicator 10.4.0.0/22 md5   # Connexions de réplication depuis le subnet
```

Le subnet `10.4.0.0/22` est le subnet AKS — tous les pods du cluster ont une IP dans cette plage (Azure CNI).

#### Scripts d'exécution

**`init-users.sh`** — exécuté par docker-entrypoint.sh lors de l'initialisation du primaire :

```bash
#!/bin/bash
set -e
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
  CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD '${REPLICATION_PASSWORD}';
EOSQL
```

| Instruction | Rôle |
|---|---|
| `set -e` | Arrête le script à la première erreur — évite une initialisation silencieusement incomplète |
| `psql -v ON_ERROR_STOP=1` | Le client psql transmet le code d'erreur SQL au shell — `set -e` peut l'intercepter |
| `--username "$POSTGRES_USER"` | Se connecte en tant que superuser (`postgres`) — seul autorisé à créer des users |
| `CREATE USER replicator WITH REPLICATION` | Crée un user avec uniquement le privilege `REPLICATION` — pas d'accès aux tables |
| `ENCRYPTED PASSWORD '${REPLICATION_PASSWORD}'` | Le mot de passe est hashé (SCRAM-SHA-256 en PG16) — jamais stocké en clair |

**Quand s'exécute-t-il :** docker-entrypoint.sh parcourt `/docker-entrypoint-initdb.d/` après `initdb` si `PGDATA` est vide. Ce n'est possible que sur `postgres-0` (le primaire) — les replicas ont un PGDATA pré-rempli par `pg_basebackup`.

---

**`init-replica.sh`** — exécuté par l'init container sur chaque pod :

```bash
#!/bin/bash
set -e

if [ "$(hostname)" = "postgres-0" ]; then   # (1)
  echo "Primary node — skipping basebackup"
  exit 0
fi

PRIMARY="postgres-0.postgres.${NAMESPACE}.svc.cluster.local"  # (2)

echo "Waiting for primary ${PRIMARY} to be ready..."
until pg_isready -h "${PRIMARY}" -p 5432 -U postgres; do      # (3)
  sleep 2
done

echo "Cleaning PGDATA before basebackup..."
rm -rf "${PGDATA:?}"/*                                         # (4)

echo "Starting pg_basebackup from ${PRIMARY}..."
PGPASSWORD="${REPLICATION_PASSWORD}" pg_basebackup \           # (5)
  -h "${PRIMARY}" \
  -D "${PGDATA}" \
  -U replicator \
  -P -Xs -R --checkpoint=fast
```

| N° | Code | Rôle |
|---|---|---|
| (1) | `if [ "$(hostname)" = "postgres-0" ]` | Sur le pod primaire, l'init container sort immédiatement — pas de basebackup sur soi-même |
| (2) | DNS headless service | `postgres-0.postgres.dev.svc.cluster.local` = DNS du pod `postgres-0` via le Service headless |
| (3) | `until pg_isready` | Boucle d'attente — le primaire peut prendre ~30s à démarrer. `pg_isready` retourne 0 quand PostgreSQL accepte des connexions |
| (4) | `rm -rf "${PGDATA:?}"/*` | Vide le répertoire de données — `pg_basebackup` exige un répertoire vide. `:?` = échec si `PGDATA` est vide (protection contre `rm -rf /*`) |
| (5) | `pg_basebackup -Xs -R` | `-Xs` = streaming WAL pendant la copie (cohérence), `-R` = génère `standby.signal` + `primary_conninfo` dans `postgresql.auto.conf` → le pod démarre en mode standby automatiquement |

---

**`liveness-check.sh`** — sonde de vie Kubernetes :

```bash
#!/bin/bash
set -e

pg_isready -U postgres || exit 1              # (1)

IS_REPLICA=$(psql -U postgres -tAc \          # (2)
  "SELECT pg_is_in_recovery();")

if [ "$IS_REPLICA" = "t" ]; then             # (3)
  WAL_ACTIVE=$(psql -U postgres -tAc \
    "SELECT count(*) FROM pg_stat_wal_receiver WHERE status IN ('streaming','catchup');")
  if [ "$WAL_ACTIVE" = "0" ]; then           # (4)
    exit 1
  fi
fi

exit 0
```

| N° | Code | Rôle |
|---|---|---|
| (1) | `pg_isready` | Vérifie que PostgreSQL répond — détecte un crash complet du process |
| (2) | `pg_is_in_recovery()` | `t` = replica, `f` = primaire. Différencie le comportement selon le rôle |
| (3) | `if [ "$IS_REPLICA" = "t" ]` | Sur le primaire, la vérification WAL n'a pas de sens — on retourne `exit 0` directement |
| (4) | `pg_stat_wal_receiver count = 0` | Le WAL Receiver est mort alors que le pod est en mode replica → réplication cassée. `exit 1` → Kubernetes redémarre le pod → init-replica.sh re-exécute `pg_basebackup` → réplication rétablie |

---

### `03-services.yaml` — Trois Services

| Service | Type | Selector | Port | Rôle |
|---|---|---|---|---|
| `postgres` (headless) | `ClusterIP: None` | `app: postgres` | 5432 | DNS individuel par pod : `postgres-0.postgres.dev.svc.cluster.local` |
| `postgres-primary` | `ClusterIP` | `statefulset.kubernetes.io/pod-name: postgres-0` | 5432 | Toujours le primaire — utilisé pour les écritures |
| `postgres-read` | `ClusterIP` | `app: postgres` | 5432 | Round-robin sur les 3 pods — lectures distribuées |

**Label `statefulset.kubernetes.io/pod-name`** : Kubernetes pose automatiquement ce label sur chaque pod d'un StatefulSet avec la valeur `<statefulset-name>-<ordinal>`. Cela permet de cibler `postgres-0` spécifiquement sans modifier les manifests.

**Service headless** : avec `clusterIP: None`, Kubernetes ne crée pas de ClusterIP. A la place, le DNS retourne directement les IPs des pods. Indispensable pour que `init-replica.sh` résolve `postgres-0.postgres.dev.svc.cluster.local` en l'IP du pod primaire.

---

### `04-statefulset.yaml` — StatefulSet principal

#### Scheduling

```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app: postgres
```

**Comportement de distribution sur 2 nœuds db :**

| Étape | pod placé | Nœud A | Nœud B | Skew | Décision |
|---|---|---|---|---|---|
| 0 | aucun | 0 | 0 | 0 | — |
| 1 | postgres-0 | 1 | 0 | 1 | ✅ ≤ maxSkew |
| 2 | postgres-1 | 1 | 1 | 0 | ✅ ≤ maxSkew (skew transitoire=0) |
| 3 | postgres-2 | 2 | 1 | 1 | ✅ ≤ maxSkew (état final stable) |

État final garanti : 2 pods sur un nœud, 1 pod sur l'autre. Le nœud le moins chargé ne peut jamais avoir 0 pod (skew dépasserait 1).

#### Init container

```yaml
initContainers:
  - name: init-replica
    image: postgres:16
    command: ["/bin/bash", "/scripts/init-replica.sh"]
```

L'init container utilise la même image que le container principal (`postgres:16`) — `pg_basebackup` et `pg_isready` sont disponibles. Il s'exécute **avant** le container principal et doit terminer avec `exit 0` pour que le container principal démarre.

#### Container principal — `args` natifs

```yaml
args:
  - -c
  - config_file=/etc/postgresql/postgresql.conf
  - -c
  - hba_file=/etc/postgresql/pg_hba.conf
```

Ces `args` sont passés à `docker-entrypoint.sh` de l'image officielle `postgres:16`. docker-entrypoint.sh passe ces arguments au binaire `postgres` via `exec gosu postgres postgres "$@"`. L'option `-c config_file=...` redirige PostgreSQL vers le fichier de configuration du ConfigMap plutôt que le fichier par défaut dans PGDATA.

**Pourquoi `args` et non `command` :** `command` remplacerait `docker-entrypoint.sh` complètement, perdant la logique d'initialisation (`initdb`, exécution `/docker-entrypoint-initdb.d/`). Avec `args`, docker-entrypoint.sh est préservé.

#### Volumes et montages

```
volumes:
  config   → ConfigMap postgres-config (postgresql.conf + pg_hba.conf)
  scripts  → ConfigMap postgres-config (init-replica.sh + init-users.sh + liveness-check.sh)

volumeMounts (container principal):
  pgdata         → /var/lib/postgresql/data          (PVC — données PostgreSQL)
  config         → /etc/postgresql                   (répertoire — 2 fichiers)
  scripts (init-users.sh)  → /docker-entrypoint-initdb.d/init-users.sh  (subPath)
  scripts (liveness-check) → /scripts/liveness-check.sh                 (subPath)
```

**`subPath`** : permet de monter un fichier individuel d'un ConfigMap à un chemin précis, sans écraser le répertoire parent. Sans `subPath`, monter le ConfigMap sur `/docker-entrypoint-initdb.d/` créerait un répertoire ConfigMap entier (lecture seule) qui remplacerait `/docker-entrypoint-initdb.d/` — les autres fichiers d'init seraient perdus.

---

## 2. Flux de connexion : Application → PostgreSQL

```
Application (namespace dev, pod IP 10.4.0.a)
  │
  │  Écriture
  ▼
Service ClusterIP "postgres-primary"  (172.16.x.x:5432)
  │  sélecte : statefulset.kubernetes.io/pod-name=postgres-0
  ▼
Pod postgres-0 (10.4.0.b:5432)  — PRIMAIRE
  │  PostgreSQL reçoit la transaction
  │  Écrit dans les fichiers de données (PGDATA)
  │  Écrit dans les WAL (Write-Ahead Log)
  │
  │  WAL Sender (processus PostgreSQL)
  ├──► WAL → postgres-1 WAL Receiver (streaming replication)
  └──► WAL → postgres-2 WAL Receiver (streaming replication)
         │
         ▼ Applique les WAL sur PGDATA replica
         postgres-1 / postgres-2 (standbys)

Application (lecture)
  │
  ▼
Service ClusterIP "postgres-read"  (172.16.y.y:5432)
  │  sélecte : app=postgres  (round-robin sur 3 pods)
  ▼
postgres-0 ou postgres-1 ou postgres-2
  │  hot_standby=on → les replicas acceptent les SELECT
  └  Le primaire (postgres-0) peut aussi recevoir des lectures
```

---

## 3. Fonctionnement du WAL et de la réplication

### Écriture PostgreSQL et WAL

```
Transaction SQL (INSERT, UPDATE, DELETE)
  │
  ├── 1. Écrit dans le WAL buffer (mémoire)
  ├── 2. Commit → flush WAL buffer → fichier WAL sur disque
  │         (durabilité ACID garantie ici)
  └── 3. En arrière-plan : apply sur les pages de données (heap files)
```

**Pourquoi WAL avant données :** si PostgreSQL crashe après le commit mais avant d'écrire sur le heap, le WAL permet de rejouer la transaction au redémarrage — c'est le principe du WAL (Write-Ahead Log).

### Streaming replication

```
Primaire (postgres-0)
  │
  │  WAL Sender process (1 par replica)
  │  Lit le WAL depuis pg_wal/ et envoie en flux TCP
  │
  ▼
Replica (postgres-1 ou postgres-2)
  │
  │  WAL Receiver process
  │  Reçoit le WAL → écrit dans pg_wal/
  │
  ▼
  Startup process (recovery)
  │  Applique le WAL sur les fichiers de données
  │  Résultat : replica == primaire (à quelques ms de lag)
```

### LSN (Log Sequence Number)

Le LSN est un pointeur dans le flux WAL — il identifie une position précise. Pour vérifier le lag de réplication :

```sql
-- Sur le primaire
SELECT
  application_name,
  pg_current_wal_lsn() - sent_lsn  AS bytes_not_sent,
  sent_lsn - write_lsn             AS bytes_not_written,
  write_lsn - flush_lsn            AS bytes_not_flushed,
  flush_lsn - replay_lsn           AS bytes_not_replayed
FROM pg_stat_replication;
```

### Récupération automatique par liveness probe

```
WAL Receiver crash (réseau, OOM, bug)
  │
  │  Pod reste "Running" — PostgreSQL process est vivant
  │  mais la réplication est cassée — invisible sans check actif
  │
  ▼
liveness-check.sh (toutes les 10s)
  │  pg_stat_wal_receiver count = 0  →  exit 1
  │
  ▼
Kubernetes : failureThreshold atteint (3 × 10s = 30s)
  │  Restart du container
  │
  ▼
init-replica.sh re-exécuté (init container)
  │  pg_basebackup depuis postgres-0
  │
  ▼
Réplication rétablie — resync complète
```

---

## 4. Ordre d'exécution des scripts

```
kubectl apply -k k8s/postgres/

  00-storageclass.yaml  → StorageClass créée (cluster-scoped)
  01-secret.yaml        → Secret postgres-credentials (namespace dev)
  02-configmap.yaml     → ConfigMap postgres-config (namespace dev)
  03-services.yaml      → 3 Services (namespace dev)
  04-statefulset.yaml   → StatefulSet postgres (namespace dev)

StatefulSet démarre les pods dans l'ordre ordinal :

  ┌─────────────────────────────────────────────────────────┐
  │ postgres-0                                              │
  │   init container init-replica                          │
  │     → hostname = postgres-0 → exit 0 immédiatement    │
  │   container postgres (docker-entrypoint.sh)            │
  │     → PGDATA vide → initdb                            │
  │     → init-users.sh → CREATE USER replicator          │
  │     → postgres démarre en mode primaire               │
  └─────────────────────────────────────────────────────────┘
            ↓  postgres-0 Ready (readinessProbe OK)
  ┌─────────────────────────────────────────────────────────┐
  │ postgres-1                                              │
  │   init container init-replica                          │
  │     → hostname = postgres-1                           │
  │     → attend que postgres-0 réponde (pg_isready)      │
  │     → pg_basebackup depuis postgres-0                 │
  │     → standby.signal + primary_conninfo créés         │
  │   container postgres                                   │
  │     → PGDATA non vide → pas d'initdb                  │
  │     → standby.signal présent → mode standby           │
  │     → WAL Receiver connecte postgres-0               │
  └─────────────────────────────────────────────────────────┘
            ↓  postgres-1 Ready
  ┌─────────────────────────────────────────────────────────┐
  │ postgres-2  (idem postgres-1)                           │
  └─────────────────────────────────────────────────────────┘
```

---

## 5. Propositions d'amélioration

### 5.1 PgBouncer — pooling de connexions

**Problème actuel :** `max_connections = 100` est partagé entre l'application, les replicas et les scripts d'ops. Chaque connexion PostgreSQL consomme ~5-10 MB RAM.

```yaml
# Déployer PgBouncer en sidecar ou Deployment séparé
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pgbouncer
  namespace: dev
spec:
  replicas: 2
  template:
    spec:
      containers:
        - name: pgbouncer
          image: bitnami/pgbouncer:1.22
          env:
            - name: POSTGRESQL_HOST
              value: postgres-primary
            - name: PGBOUNCER_POOL_MODE
              value: transaction
            - name: PGBOUNCER_MAX_CLIENT_CONN
              value: "1000"
            - name: PGBOUNCER_DEFAULT_POOL_SIZE
              value: "20"
```

Avec PgBouncer en mode `transaction` : 1 000 connexions clients → 20 connexions réelles PostgreSQL.

---

### 5.2 Monitoring avec pgmetrics / Prometheus

```yaml
# Sidecar postgres_exporter
containers:
  - name: postgres-exporter
    image: prometheuscommunity/postgres-exporter:v0.15.0
    env:
      - name: DATA_SOURCE_NAME
        value: "postgresql://postgres:$(POSTGRES_PASSWORD)@localhost:5432/postgres?sslmode=disable"
    ports:
      - name: metrics
        containerPort: 9187
```

Métriques clés : `pg_replication_lag`, `pg_stat_activity_count`, `pg_database_size_bytes`.

---

### 5.3 Augmenter `wal_keep_size` selon le lag acceptable

Scénario : réseau lent entre pods → lag > 128 MB → le primaire tronque les WAL → `pg_basebackup` complet requis.

```
wal_keep_size = 512MB  # Garde 512 MB de WAL — couvre ~5-10 minutes de lag élevé
```

Surveiller le lag avant d'augmenter :
```sql
SELECT pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS lag_bytes
FROM pg_stat_replication;
```

---

### 5.4 Sauvegardes avec `pg_dump` ou WAL-G

```bash
# CronJob pour pg_dump quotidien
kubectl apply -n dev -f - <<EOF
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgres-backup
spec:
  schedule: "0 2 * * *"  # 02:00 UTC chaque nuit
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: backup
              image: postgres:16
              command:
                - /bin/bash
                - -c
                - |
                  PGPASSWORD=${POSTGRES_PASSWORD} pg_dump \
                    -h postgres-primary \
                    -U postgres \
                    -Fc \
                    postgres > /backup/postgres-$(date +%Y%m%d).dump
              volumeMounts:
                - name: backup-storage
                  mountPath: /backup
          restartPolicy: OnFailure
          volumes:
            - name: backup-storage
              persistentVolumeClaim:
                claimName: postgres-backup-pvc
EOF
```

---

### 5.5 Restreindre `max_connections` et activer `shared_buffers`

En production, adapter `postgresql.conf` dans le ConfigMap selon la RAM disponible :

```
# Pour Standard_D4s_v3 (16 GB RAM)
shared_buffers = 4GB               # 25% de la RAM — cache PostgreSQL
effective_cache_size = 12GB        # 75% de la RAM — hint pour le planner
work_mem = 64MB                    # Par opération de tri
maintenance_work_mem = 1GB         # Pour VACUUM, CREATE INDEX
max_connections = 200
```

Règle : `shared_buffers` = 25% de la RAM. Au-delà de 8 GB, les gains sont diminués.