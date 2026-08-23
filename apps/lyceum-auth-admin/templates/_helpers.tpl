{{- define "lyceum-auth-admin.labels" -}}
app.kubernetes.io/name: lyceum-auth-admin
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "lyceum-auth-admin.image" -}}
{{- printf "%s/%s:%s" (include "cluster.registry" .ctx) .image.repository .image.tag -}}
{{- end }}

{{- define "lyceum-auth-admin.apiFqdn" -}}
{{- printf "api.%s" (include "cluster.fqdn" (dict "ctx" .ctx "prefix" .prefix)) -}}
{{- end }}