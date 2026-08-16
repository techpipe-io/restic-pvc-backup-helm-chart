# restic-pvc-backup

A small Helm chart for scheduled Restic backups of Kubernetes PVCs to S3/S3-compatible (or any other Restic repository), with path-level include/exclude rules, retention/prune, independent periodic data-integrity verification, Prometheus monitoring, and a Grafana dashboard.

Chart version: **0.2.0**  
Restic image: **0.19.1**

## Backup lifecycle

The primary CronJob mounts selected PVCs read-only and runs:

```text
restic backup
    -> restic forget [retention] --prune
    -> restic check
```

Retention is executed immediately after every successful backup, as requested. If backup fails, retention/prune is skipped. The normal structural `restic check` still runs and the Job exits non-zero if any required step fails.

A second independent CronJob performs deeper verification:
This separation avoids downloading repository data after every daily backup.

## PVC and path selection

```yaml
backup:
  targets:
    - name: data
      claimName: data
      include:
        - data/git/repositories
        - data/attachments
        - data/lfs
      exclude:
        - data/log/**
        - data/indexers/**
        - tmp/**
```

`include` entries are literal paths relative to the PVC root. Empty `include` means the entire PVC. `exclude` entries are Restic exclude patterns relative to that PVC root.

The chart mounts every target as `/backup/<target-name>` and generates `--files-from-verbatim` and `--exclude-file` inputs.

### Application consistency

This chart backs up a **live filesystem view**. Mounting a PVC read-only in the backup Pod does not freeze writes made by the application Pod. For applications that require database/filesystem coordination, pair this chart with an application-aware database dump or a controlled quiesce/maintenance procedure when strict point-in-time consistency is required.

## Repository Secret

Recommended S3-compatible Secret:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: backup-restic-repository
stringData:
  RESTIC_REPOSITORY: s3:https://s3.example.net/backups/repo
  RESTIC_PASSWORD: change-me
  AWS_ACCESS_KEY_ID: change-me
  AWS_SECRET_ACCESS_KEY: change-me
```

Prefer External Secrets/Vault, SOPS or Sealed Secrets rather than committing credentials to Helm values.

## Repository lock handling

Backup/retention and periodic integrity verification are separate CronJobs, so their schedules can occasionally overlap. `repository.retryLock` is passed through Restic's global `--retry-lock` option:

```yaml
repository:
  retryLock: "15m"
```

This does not replace sensible scheduling, but avoids an unnecessary failure when prune briefly holds an exclusive repository lock.

## Stable host identity and retention

CronJob Pod names change on every execution, so the chart sets a stable Restic host identity:

```yaml
backup:
  host: haskel-pvc
```

The default retention grouping is:

```yaml
retention:
  groupBy: "host,tags"
```

A separate Restic repository path per application is still recommended.

## Retention

All common Restic retention controls are exposed:

```yaml
retention:
  enabled: true
  prune: true
  groupBy: "host,tags"

  keepLast: ""
  keepHourly: ""
  keepDaily: "7"
  keepWeekly: "4"
  keepMonthly: "6"
  keepYearly: "1"

  keepWithin: ""
  keepWithinHourly: ""
  keepWithinDaily: ""
  keepWithinWeekly: ""
  keepWithinMonthly: ""
  keepWithinYearly: ""

  keepTags: []
  extraArgs: []
```

Cleanup is run immediately after every successful backup with `restic forget ... --prune`.

For very large S3 repositories, pruning after every backup can increase object-storage operations. Set `retention.prune: false` only if you intentionally move physical pruning to another maintenance workflow.

## Fast check after every backup

Default:

```yaml
check:
  enabled: true
  readData: false
  readDataSubset: ""
```

This runs a structural `restic check` after backup and retention.

## Periodic integrity verification

The second CronJob supports three modes.

### Subset — recommended default

```yaml
integrityCheck:
  enabled: true
  schedule: "45 4 * * 0"
  timeZone: "Europe/Belgrade"
  mode: subset
  readDataSubset: "10%"
```

`.spec.timeZone` is optional in the chart; leave it empty on clusters that do not support the field. CronJob time-zone support is stable in Kubernetes 1.27+.

Equivalent to:

```bash
restic check --read-data-subset=10%
```

Restic also accepts subset forms such as `2.5%`, `10G`, or deterministic partitions such as `1/5`.

### Full repository read

```yaml
integrityCheck:
  mode: full
```

Equivalent to:

```bash
restic check --read-data
```

This downloads and verifies every repository pack and can be expensive for remote object storage.

### Metadata-only

```yaml
integrityCheck:
  mode: metadata
```

Runs ordinary `restic check` independently of the backup cycle.

By default `withCache: false`, so integrity verification does not intentionally trust/reuse an existing Restic cache. Set it to `true` only when you explicitly want `check --with-cache`.

## Prometheus architecture

The chart deliberately uses two data sources rather than Pushgateway:

```text
restic-exporter
  -> repository size
  -> retained snapshot count
  -> newest snapshot timestamp
  -> backup logical size
  -> incremental bytes added
  -> backup duration
  -> Restic client_version label
  -> repository locks

kube-state-metrics
  -> backup CronJob success/failure state
  -> integrity CronJob success/failure state
  -> last successful execution
  -> active/running state
```

This is important because a failed backup does not create a Restic snapshot and therefore cannot be discovered from repository contents alone.

The bundled exporter currently exposes metrics including:

```text
restic_size_total
restic_uncompressed_size_total
restic_compression_ratio
restic_blob_count_total
restic_snapshots_total
restic_backup_timestamp
restic_backup_files_total
restic_backup_size_total
restic_backup_files_new
restic_backup_files_changed
restic_backup_files_unmodified
restic_backup_data_added_bytes
restic_backup_duration_seconds
restic_locks_total
restic_scrape_duration_seconds
```

The newest snapshot metrics carry `client_version`, used by the Grafana dashboard to display the Restic client version.

`exporter.noCheck` defaults to `true`: the dedicated backup/integrity jobs already perform repository checks, so an exporter-driven check would duplicate repository reads. `restic_check_success` is only available when `exporter.noCheck: false`.

### Retention observability

The exporter exposes the **resulting retained snapshot count** (`restic_snapshots_total`) rather than Restic's configured retention policy. The bundled Grafana dashboard therefore displays both:

- retained snapshot count from Prometheus;
- configured keep-daily/weekly/monthly/yearly policy from Helm values.

## ServiceMonitor

```yaml
serviceMonitor:
  enabled: true
  interval: 60s
  scrapeTimeout: 30s
  additionalLabels:
    release: kube-prometheus-stack
```

`jobLabel` is configured so exporter metrics use the stable Helm release fullname as the Prometheus `job` label.

## PrometheusRule

Enable in a kube-prometheus-stack/Prometheus Operator cluster:

```yaml
prometheusRule:
  enabled: true
  additionalLabels:
    release: kube-prometheus-stack
```

Bundled alerts:

- `ResticPVCBackupLatestRunFailed` — latest scheduled backup did not complete successfully;
- `ResticPVCBackupStale` — no successful backup within the configured threshold;
- `ResticPVCBackupRunningTooLong`;
- `ResticPVCIntegrityLatestRunFailed`;
- `ResticPVCIntegrityCheckStale`;
- `ResticPVCIntegrityCheckRunningTooLong`;
- `ResticExporterDown`;
- `ResticRepositoryLockedTooLong`;
- optional `ResticRepositoryExporterCheckFailed` when exporter-driven checks are enabled.

The latest-run alerts use `kube_cronjob_status_last_schedule_time`, `kube_cronjob_status_last_successful_time`, and `kube_cronjob_status_active`. This is more useful than alerting on retained `kube_job_status_failed` objects, because a failed Job can remain in Kubernetes history after a later successful run.

## Grafana dashboard

`grafanaDashboard.enabled: true` creates a ConfigMap labeled by default with:

```yaml
grafana_dashboard: "1"
```

which matches the usual kube-prometheus-stack Grafana sidecar convention. Labels and annotations are configurable.

The dashboard includes:

- latest snapshot age;
- repository size;
- retained snapshots;
- latest incremental bytes added;
- backup duration;
- periodic integrity-check age;
- Restic client version;
- successful/failed backup and integrity Jobs over the selected Grafana range (from kube-state-metrics history in Prometheus);
- repository size/data-added/duration/logical-size time series;
- repository locks;
- exporter state and scan duration;
- backup/integrity active state;
- rendered retention/integrity policy.

The dashboard has a Prometheus datasource variable and generates a per-release UID by default, so multiple backup releases do not overwrite each other's dashboards.

## Install

```bash
helm upgrade --install backup ./restic-pvc-backup -f example-values.yaml
```

Manual backup:

```bash
kubectl create job \
  --from=cronjob/backup-restic-pvc-backup backup-manual-$(date +%s)
```

Manual integrity verification:

```bash
kubectl create job \
  --from=cronjob/backup-restic-pvc-backup-integrity \
  integrity-manual-$(date +%s)
```

Use `helm template` or the release NOTES to obtain the exact CronJob names when a long release/chart name is truncated to Kubernetes' CronJob naming limit.

## Restore

The chart intentionally does not automate destructive in-place restores. Inspect first:

```bash
restic snapshots
restic ls latest
```

Restore to a temporary directory/PVC, validate the result, then replace production data deliberately.
