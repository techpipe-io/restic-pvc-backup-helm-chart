# Changelog

## 0.2.0

- Added independent scheduled integrity verification CronJob.
- Added `metadata`, `subset`, and `full` integrity modes.
- Added `repository.retryLock` for overlapping Restic operations.
- Added separate resources, scheduling, and cache settings for integrity checks.
- Added bundled Grafana dashboard ConfigMap.
- Added PrometheusRule coverage for backup/integrity failures, stale runs, long-running jobs, exporter availability, and repository locks.
- Added `values.schema.json`.
- Added CronJob-safe name truncation.

## 0.1.0

- Initial PVC backup CronJob.
- Path-level include/exclude support.
- Immediate retention/prune after backup.
- Structural repository check.
- restic-exporter, Service, ServiceMonitor, and initial alerting support.
