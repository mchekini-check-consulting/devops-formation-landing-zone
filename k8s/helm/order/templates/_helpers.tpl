{{- define "order.labels" -}}
app: {{ .Chart.Name }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "order.selectorLabels" -}}
app: {{ .Chart.Name }}
{{- end }}
