{{/*
Expand the name of the chart.
*/}}
{{- define "zgw-posix.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "zgw-posix.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "zgw-posix.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{ include "zgw-posix.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels
*/}}
{{- define "zgw-posix.selectorLabels" -}}
app.kubernetes.io/name: {{ include "zgw-posix.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Name of the TLS secret to mount for pod-level TLS.
Priority: existingSecret > openshiftServingCert (auto-named by OCP).
*/}}
{{- define "zgw-posix.tlsSecretName" -}}
{{- if .Values.podTLS.existingSecret -}}
  {{- .Values.podTLS.existingSecret -}}
{{- else if .Values.podTLS.openshiftServingCert -}}
  {{- include "zgw-posix.fullname" . }}-serving-cert
{{- end -}}
{{- end -}}

{{/*
Full image path for the Browser UI container.
Constructs: registry/repository:tag
*/}}
{{- define "zgw-posix.browserUi.image" -}}
{{- printf "%s/%s:%s" .Values.browserUi.registry.server .Values.browserUi.image.ui.repository .Values.browserUi.image.ui.tag -}}
{{- end -}}

{{/*
Name of the image pull secret for the Browser UI.
*/}}
{{- define "zgw-posix.browserUi.imagePullSecretName" -}}
{{- .Values.browserUi.registry.secretName -}}
{{- end -}}
