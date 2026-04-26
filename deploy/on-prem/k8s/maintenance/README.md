# OpenBrain — PostgreSQL Backup & Maintenance

Automated nightly backup + weekly maintenance for the on-prem `openbrain-postgres-0` StatefulSet.

## What this provides

| CronJob | Schedule (UTC) | Purpose |
|---------|---------------|---------|
| `openbrain-pg-logical-backup` | `0 2 * * *` (daily 02:00) | `pg_dump` to NAS, gzipped, 30-day retention, JSON manifest |
| `openbrain-pg-maintenance` | `0 1 * * 0` (Sun 01:00) | VACUUM ANALYZE, bloat report, unused-index report, idle-tx reaper, pgvector index inventory |

## Pattern

Both jobs use **`bitnami/kubectl:latest`** as the runner and `kubectl exec` into `openbrain-postgres-0` to invoke `pg_dump` / `psql` over the in-pod socket. No `PGPASSWORD` is sent over the network and no DB credentials are mounted into the runner.

> Tag note: `bitnami/kubectl` publishes only `:latest` plus immutable digest tags on Docker Hub. Pinned-version tags like `:1.31` do **not** exist.

A dedicated ServiceAccount (`openbrain-pg-maintenance`) holds a Role limited to `pods get/list` and `pods/exec create` in the `openbrain` namespace.

## Backup target

NAS hostPath: `/mnt/nas-backup/postgresql/openbrain/logical_backups/`
(every node mounts `//192.168.68.100/F-Share/Databases` at `/mnt/nas-backup`).

Files written each run:
- `openbrain_<ts>.sql.gz` — gzipped plain-format dump (`--no-owner --no-privileges --clean --if-exists`)
- `manifest_<ts>.json` — per-table sizes & row counts from `pg_stat_user_tables`
- `backup_<ts>.log` — pg_dump stderr

A `MIN_BACKUP_SIZE` guard (10 KB) fails the job if the dump came back suspiciously empty.

## Apply

```bash
kubectl apply -f deploy/on-prem/k8s/maintenance/
```

## Smoke test

```bash
# Backup
kubectl create job --from=cronjob/openbrain-pg-logical-backup openbrain-pg-backup-test -n openbrain
kubectl wait --for=condition=complete --timeout=600s job/openbrain-pg-backup-test -n openbrain
kubectl logs -n openbrain -l job-name=openbrain-pg-backup-test --tail=80

# Maintenance
kubectl create job --from=cronjob/openbrain-pg-maintenance openbrain-pg-maintenance-test -n openbrain
kubectl wait --for=condition=complete --timeout=600s job/openbrain-pg-maintenance-test -n openbrain
kubectl logs -n openbrain -l job-name=openbrain-pg-maintenance-test --tail=120
```

## Restore (manual)

```bash
# Copy a dump off the NAS, decompress, and replay against a target DB:
gunzip -c openbrain_<ts>.sql.gz | psql -U openbrain -d openbrain
```

The dump is emitted with `--clean --if-exists`, so it will drop and recreate objects (including the `vector` extension) on the target.

## pgvector

The image is `pgvector/pgvector:pg17`. Plain `pg_dump` emits `CREATE EXTENSION vector;` and the column data, so backups round-trip on any host with pgvector installed. HNSW/IVFFlat **REINDEX is not automated** — the weekly maintenance job reports vector index sizes so you can decide when to schedule a manual reindex.

## Origin

Pattern adopted from upick-prod's `postgres-prod-logical-backup` and `postgres-prod-maintenance` CronJobs, mirrored from rummag-dev's `infrastructure/kubernetes/base/maintenance/` overlay (2026-04-26).
