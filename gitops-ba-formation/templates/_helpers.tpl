{{/*
Évalue une chaîne des values avec tpl.
Entrée : dict "value" <chaîne> "ctx" <contexte>
$currentEnv est déclaré en tête de la chaîne, car tpl ne voit pas
les variables du template appelant.
*/}}
{{- define "mca.tpl" -}}
{{- tpl (printf "{{- $currentEnv := .env -}}%s" (toString .value)) .ctx -}}
{{- end -}}

{{/*
Contenu du ConfigMap d'une application (réutilisé pour le checksum du Deployment).
Entrée : dict "app" <app> "ctx" <contexte>
*/}}
{{- define "mca.configData" -}}
{{- range .app.envList }}
{{ .key }}: {{ include "mca.tpl" (dict "value" .value "ctx" $.ctx) | quote }}
{{- end }}
{{- end -}}

{{/* Labels communs. Entrée : dict "app" <app> "env" <env> "project" <projet> */}}
{{- define "mca.labels" -}}
app: {{ .app.name }}
tier: {{ .app.type }}
env: {{ .env }}
project: {{ .project }}
{{- end -}}

{{/* Labels de sélection (immuables sur un Deployment : ne pas y ajouter "tier") */}}
{{- define "mca.selectorLabels" -}}
app: {{ .app.name }}
env: {{ .env }}
project: {{ .project }}
{{- end -}}
