{{- define "lyceum-auth.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "lyceum-auth.fullname" -}}
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

{{- define "lyceum-auth.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "lyceum-auth.labels" -}}
helm.sh/chart: {{ include "lyceum-auth.chart" . }}
app.kubernetes.io/name: {{ include "lyceum-auth.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "lyceum-auth.selectorLabels" -}}
app.kubernetes.io/name: {{ include "lyceum-auth.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "lyceum-auth.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "lyceum-auth.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "lyceum-auth.host" -}}
{{- include "cluster.fqdn" (dict "ctx" . "prefix" .Values.hostPrefix) -}}
{{- end }}

{{- define "lyceum-auth.apiHost" -}}
{{- printf "api.%s" (include "lyceum-auth.host" .) -}}
{{- end }}

{{- define "lyceum-auth.authentikUrl" -}}
{{- include "cluster.url" (dict "ctx" . "prefix" .Values.authentikHostPrefix) -}}
{{- end }}

{{- define "lyceum-auth.postgresHost" -}}
{{- if .Values.config.postgres.host -}}
{{- .Values.config.postgres.host -}}
{{- else -}}
{{- printf "%s-postgresql.%s.svc.cluster.local" (include "lyceum-auth.fullname" .) .Release.Namespace -}}
{{- end -}}
{{- end }}

{{- define "lyceum-auth.allowedOrigins" -}}
{{- list (include "cluster.url" (dict "ctx" . "prefix" .Values.hostPrefix)) | toJson -}}
{{- end }}

{{- define "lyceum-auth.image" -}}
{{- if .Values.image.tag }}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag }}
{{- else }}
{{- printf "%s:%s" .Values.image.repository .Chart.AppVersion }}
{{- end }}
{{- end }}