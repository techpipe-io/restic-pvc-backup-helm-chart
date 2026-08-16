{{- define "restic-pvc-backup.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "restic-pvc-backup.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}


{{- define "restic-pvc-backup.backupCronJobName" -}}
{{- (include "restic-pvc-backup.fullname" .) | trunc 52 | trimSuffix "-" }}
{{- end }}

{{- define "restic-pvc-backup.integrityName" -}}
{{- printf "%s-integrity" ((include "restic-pvc-backup.fullname" .) | trunc 42 | trimSuffix "-") | trunc 52 | trimSuffix "-" }}
{{- end }}

{{- define "restic-pvc-backup.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "restic-pvc-backup.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "restic-pvc-backup.selectorLabels" -}}
app.kubernetes.io/name: {{ include "restic-pvc-backup.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "restic-pvc-backup.secretName" -}}
{{- if .Values.repository.existingSecret -}}
{{- .Values.repository.existingSecret -}}
{{- else if .Values.repository.secretName -}}
{{- .Values.repository.secretName -}}
{{- else -}}
{{- printf "%s-repository" ((include "restic-pvc-backup.fullname" .) | trunc 52 | trimSuffix "-") | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end }}

{{- define "restic-pvc-backup.dashboardUID" -}}
{{- if .Values.grafanaDashboard.uid -}}
{{- .Values.grafanaDashboard.uid -}}
{{- else -}}
{{- printf "restic-%s" (printf "%s/%s" .Release.Namespace (include "restic-pvc-backup.fullname" .) | sha256sum | trunc 12) -}}
{{- end -}}
{{- end }}

{{- define "restic-pvc-backup.dashboardTitle" -}}
{{- if .Values.grafanaDashboard.title -}}
{{- .Values.grafanaDashboard.title -}}
{{- else -}}
{{- printf "Restic PVC Backup - %s" (include "restic-pvc-backup.fullname" .) -}}
{{- end -}}
{{- end }}

{{- define "restic-pvc-backup.configName" -}}
{{- printf "%s-config" ((include "restic-pvc-backup.fullname" .) | trunc 56 | trimSuffix "-") | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "restic-pvc-backup.exporterName" -}}
{{- printf "%s-exporter" ((include "restic-pvc-backup.fullname" .) | trunc 54 | trimSuffix "-") | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "restic-pvc-backup.dashboardConfigName" -}}
{{- printf "%s-grafana-dashboard" ((include "restic-pvc-backup.fullname" .) | trunc 45 | trimSuffix "-") | trunc 63 | trimSuffix "-" }}
{{- end }}
