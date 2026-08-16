{{- define "authentik.name" -}}
authentik
{{- end }}

{{- define "authentik.fullname" -}}
{{ .Release.Name }}
{{- end }}

{{- define "authentik.labels" -}}
app.kubernetes.io/name: {{ include "authentik.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}