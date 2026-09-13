{{/*
Expand the name of the chart.
*/}}
{{- define "ecommerce.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "ecommerce.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "ecommerce.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "ecommerce.labels" -}}
helm.sh/chart: {{ include "ecommerce.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "ecommerce.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ecommerce.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Namespace
*/}}
{{- define "ecommerce.namespace" -}}
{{- .Values.global.namespace }}
{{- end }}

{{/*
ServiceAccount name for a workload (defaults to the service/deployment name).
Usage: include "ecommerce.serviceAccountName" (dict "root" . "name" "product-service")
*/}}
{{- define "ecommerce.serviceAccountName" -}}
{{- $root := .root -}}
{{- $name := .name -}}
{{- if and $root.Values.serviceAccounts $root.Values.serviceAccounts.names (hasKey $root.Values.serviceAccounts.names $name) -}}
{{- index $root.Values.serviceAccounts.names $name -}}
{{- else -}}
{{- $name -}}
{{- end -}}
{{- end }}

{{/*
Standard pod labels for mesh-aware workloads.
Usage: include "ecommerce.podLabels" (dict "app" "product-service")
*/}}
{{- define "ecommerce.podLabels" -}}
app: {{ .app }}
{{- end }}

{{/*
OpenTelemetry env vars (rendered only when .Values.tracing.enabled).
Usage: pass a dict with `serviceName`:
    {{- include "ecommerce.otelEnv" (dict "root" . "serviceName" "order-service") | nindent 12 }}
*/}}
{{- define "ecommerce.otelEnv" -}}
{{- $root := .root -}}
{{- if $root.Values.tracing.enabled }}
- name: OTEL_SERVICE_NAME
  value: {{ .serviceName | quote }}
- name: OTEL_EXPORTER_OTLP_ENDPOINT
  value: {{ $root.Values.tracing.endpoint | quote }}
- name: OTEL_EXPORTER_OTLP_PROTOCOL
  value: "http/protobuf"
- name: OTEL_TRACES_EXPORTER
  value: "otlp"
- name: OTEL_METRICS_EXPORTER
  value: "none"
- name: OTEL_LOGS_EXPORTER
  value: "none"
- name: OTEL_PROPAGATORS
  value: "tracecontext,baggage"
- name: OTEL_TRACES_SAMPLER
  value: "parentbased_traceidratio"
- name: OTEL_TRACES_SAMPLER_ARG
  value: {{ $root.Values.tracing.samplerArg | quote }}
- name: OTEL_RESOURCE_ATTRIBUTES
  value: {{ printf "deployment.environment=%s,service.namespace=ecommerce,k8s.namespace.name=%s" $root.Values.tracing.environment (include "ecommerce.namespace" $root) | quote }}
{{- end }}
{{- end }}
