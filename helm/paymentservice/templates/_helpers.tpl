{{- define "service.name" -}}{{ .Chart.Name }}{{- end -}}
{{- define "service.fullname" -}}{{ .Release.Name }}-{{ .Chart.Name }}{{- end -}}
{{- define "service.labels" -}}
app.kubernetes.io/name: {{ include "service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: online-boutique
{{- end -}}
