{{- define "front.labels" -}}
app: {{ .Chart.Name }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "front.selectorLabels" -}}
app: {{ .Chart.Name }}
{{- end }}
