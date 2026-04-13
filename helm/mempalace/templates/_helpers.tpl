{{/*
Expand the name of the chart.
*/}}
{{- define "mempalace.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this
(by the DNS naming spec).  If the release name contains the chart name it will
be used as-is.
*/}}
{{- define "mempalace.fullname" -}}
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

{{/*
Create chart label value (chart name + version).
*/}}
{{- define "mempalace.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels applied to every resource.
*/}}
{{- define "mempalace.labels" -}}
helm.sh/chart: {{ include "mempalace.chart" . }}
{{ include "mempalace.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels (stable – must not change after first deploy).
*/}}
{{- define "mempalace.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mempalace.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Resolve the ServiceAccount name.
*/}}
{{- define "mempalace.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "mempalace.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Resolve the container image tag.
Falls back to .Chart.AppVersion when values.image.tag is empty.
*/}}
{{- define "mempalace.image" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion }}
{{- printf "%s:%s" .Values.image.repository $tag }}
{{- end }}

{{/*
Name of the data PVC (single volume covering palace + WAL).
*/}}
{{- define "mempalace.dataPvcName" -}}
{{- printf "%s-data" (include "mempalace.fullname" .) }}
{{- end }}
