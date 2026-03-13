{{/*
Chart 短名（截断 63 字符）
*/}}
{{- define "openclaw-cookbook.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Release 全名（截断 63 字符）
如果 release name 已包含 chart name 则不重复拼接
*/}}
{{- define "openclaw-cookbook.fullname" -}}
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
Chart 版本标签（用于 helm.sh/chart label）
*/}}
{{- define "openclaw-cookbook.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
标准 K8s 标签集
*/}}
{{- define "openclaw-cookbook.labels" -}}
helm.sh/chart: {{ include "openclaw-cookbook.chart" . }}
{{ include "openclaw-cookbook.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
选择器标签（仅 name + instance）
*/}}
{{- define "openclaw-cookbook.selectorLabels" -}}
app.kubernetes.io/name: {{ include "openclaw-cookbook.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
