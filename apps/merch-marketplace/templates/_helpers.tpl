{{- define "merch.image" -}}
{{- printf "%s/%s:%s" (include "cluster.registry" .ctx) .image.repository .image.tag -}}
{{- end -}}
