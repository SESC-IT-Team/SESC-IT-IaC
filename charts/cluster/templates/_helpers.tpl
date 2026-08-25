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

{{- define "cluster.apiFqdn" -}}
{{- include "cluster.fqdn" (dict "ctx" .ctx "prefix" (printf "api.%s" .prefix)) -}}
{{- end }}

{{- define "cluster.url" -}}
{{- printf "https://%s.%s" .prefix (include "cluster.baseDomain" .ctx) -}}
{{- end }}

{{- define "cluster.apiUrl" -}}
{{- printf "https://%s" (include "cluster.apiFqdn" .) -}}
{{- end }}

{{- define "cluster.privateImage" -}}
{{- printf "%s/%s:%s" (include "cluster.registry" .) .Values.image.repository .Values.image.tag -}}
{{- end }}

{{- define "cluster.internalCAMount" -}}
{{- if and .Values.global .Values.global.internalCA .Values.global.internalCA.enabled }}
- name: internal-ca
  mountPath: {{ default "/etc/ssl/certs/sesc-internal-ca.crt" .Values.global.internalCA.mountPath | quote }}
  subPath: ca.crt
  readOnly: true
{{- end }}
{{- end }}

{{- define "cluster.internalCAEnv" -}}
{{- if and .Values.global .Values.global.internalCA .Values.global.internalCA.enabled }}
- name: SSL_CERT_FILE
  value: {{ default "/etc/ssl/certs/sesc-internal-ca.crt" .Values.global.internalCA.mountPath | quote }}
- name: REQUESTS_CA_BUNDLE
  value: {{ default "/etc/ssl/certs/sesc-internal-ca.crt" .Values.global.internalCA.mountPath | quote }}
{{- end }}
{{- end }}

{{- define "cluster.internalCAVolume" -}}
{{- if and .Values.global .Values.global.internalCA .Values.global.internalCA.enabled }}
- name: internal-ca
  configMap:
    name: {{ default "sesc-internal-ca" .Values.global.internalCA.configMapName }}
    items:
      - key: ca.crt
        path: ca.crt
{{- end }}
{{- end }}
