# Redmine Helm repository

This repository contains a small Helm chart for scheduled Restic backups of Kubernetes PVCs to S3/S3-compatible (or any other Restic repository), with path-level include/exclude rules, retention/prune, independent periodic data-integrity verification, Prometheus monitoring, and a Grafana dashboard.

The chart itself lives in `charts/restic-pvc-backup`, refer to its [README.md](charts/restic-pvc-backup/README.md) for details. 
