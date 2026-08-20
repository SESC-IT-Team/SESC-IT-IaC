{{- define "cluster.baseDomain" -}}
{{- $fromGlobal := "" -}}
{{- if and .Values.global .Values.global.baseDomain -}}
{{- $fromGlobal = .Values.global.baseDomain -}}
{{- end -}}
{{- $fromSubchart := "" -}}
{{- if and (index .Values "cluster") (index .Values "cluster" "global") -}}
{{- $fromSubchart = index .Values "cluster" "global" "baseDomain" -}}
{{- end -}}
{{- $domain := default $fromSubchart $fromGlobal -}}
{{- required "global.baseDomain must be set in charts/cluster/values.yaml" $domain -}}
{{- end }}

{{- define "cluster.registry" -}}
{{- printf "reg.%s" (include "cluster.baseDomain" .) -}}
{{- end }}

{{- define "cluster.fqdn" -}}
{{- printf "%s.%s" .prefix (include "cluster.baseDomain" .ctx) -}}
{{- end }}

{{- define "cluster.url" -}}
{{- printf "https://%s.%s" .prefix (include "cluster.baseDomain" .ctx) -}}
{{- end }}

{{- define "cluster.privateImage" -}}
{{- printf "%s/%s:%s" (include "cluster.registry" .) .Values.image.repository .Values.image.tag -}}
{{- end }}
