# Procedure de Restore PostgreSQL

---

## Etape 1 — Etat initial (avant destruction)

### Les bases existent et contiennent des donnees

```bash
kubectl exec -n dev postgres-0 -- psql -U postgres -c "\l"
kubectl exec -n dev postgres-0 -- psql -U formation -d catalogue -c "SELECT count(*) FROM products;"
kubectl exec -n dev postgres-0 -- psql -U formation -d payment -c "SELECT count(*) FROM payments;"
```

### Les utilisateurs existent

```bash
kubectl exec -n dev postgres-0 -- psql -U postgres -c "\du"
```

### Les microservices fonctionnent

```bash
kubectl get pods -n dev
```

---

## Etape 2 — Lister les backups disponibles

```bash
az storage blob list \
  --account-name stformationecombackup \
  --container-name postgres-backups \
  --prefix dev/ \
  --auth-mode login \
  --query "[].{Nom:name, Taille:properties.contentLength, Date:properties.lastModified}" \
  -o table
```

---

## Etape 3 — Simuler la perte complete (bases + utilisateurs)

### 3.1 — Scaler les deployments a 0

```bash
kubectl scale deployment pgpool catalogue order payment -n dev --replicas=0
```

### 3.2 — Terminer les connexions actives

```bash
kubectl exec -n dev postgres-0 -- psql -U postgres -c "
  SELECT pg_terminate_backend(pid)
  FROM pg_stat_activity
  WHERE datname IN ('catalogue', 'order', 'payment')
  AND pid <> pg_backend_pid();
"
```

### 3.3 — Supprimer les bases

```bash
kubectl exec -n dev postgres-0 -- psql -U postgres \
  -c "DROP DATABASE catalogue;" \
  -c "DROP DATABASE \"order\";" \
  -c "DROP DATABASE payment;"
```

### 3.4 — Supprimer les utilisateurs

> **Note** : on ne supprime pas `replicator` pour ne pas casser la replication entre les pods PostgreSQL.

```bash
kubectl exec -n dev postgres-0 -- psql -U postgres \
  -c "DROP USER formation;" \
  -c "DROP USER backup;" \
  -c "DROP USER restore;"
```

### Verifier que les bases n'existent plus

```bash
kubectl exec -n dev postgres-0 -- psql -U postgres -c "\l"
```

### Verifier que les utilisateurs n'existent plus

```bash
kubectl exec -n dev postgres-0 -- psql -U postgres -c "\du"
```

---

## Etape 4 — Lancer le restore

```bash
kubectl delete job pg-restore -n postgres-backup --ignore-not-found && \
export BACKUP_FILENAME="20260606-000002.tar" && \
envsubst '${BACKUP_FILENAME}' < k8s/postgres-backup/04-restore-job.yaml | kubectl apply -f -
```

---

## Etape 5 — Suivre la progression

```bash
kubectl logs -n postgres-backup -l job-name=pg-restore --all-containers -f
```

Le job execute 6 etapes :

1. Acquisition d'un token Azure (Workload Identity)
2. Telechargement du backup depuis le Blob Storage
3. Extraction de l'archive (`.tar` contient un `.sql.gz` + `.sha256`)
4. Verification du checksum SHA-256
5. Decompression du dump SQL
6. Restauration via `psql -f` sur le primary

---

## Etape 6 — Verification post-restore

### Les bases sont revenues

```bash
kubectl exec -n dev postgres-0 -- psql -U postgres -c "\l"
```

### Les utilisateurs sont revenus

```bash
kubectl exec -n dev postgres-0 -- psql -U postgres -c "\du"
```

### Les donnees sont intactes

```bash
kubectl exec -n dev postgres-0 -- psql -U formation -d catalogue -c "SELECT count(*) FROM products;"
kubectl exec -n dev postgres-0 -- psql -U formation -d payment -c "SELECT count(*) FROM payments;"
```

---

## Etape 7 — Remettre les microservices en ligne

```bash
kubectl scale deployment pgpool     -n dev --replicas=2 && \
kubectl scale deployment catalogue  -n dev --replicas=2 && \
kubectl scale deployment order      -n dev --replicas=2 && \
kubectl scale deployment payment    -n dev --replicas=2
```

### Verifier que les microservices fonctionnent

```bash
kubectl get pods -n dev -w
```

---

## Etape 8 — Verifier la replication

```bash
kubectl exec -n dev postgres-0 -- psql -U postgres -c \
  "SELECT client_addr, state, sent_lsn, replay_lsn FROM pg_stat_replication;"
```
