# Blocky Configuration
# Generated from Home Assistant add-on options
# Reference: https://0xerr0r.github.io/blocky/latest/configuration/
#
# IMPORTANT: To edit this file directly, enable "Custom Configuration" in the add-on UI.
# When custom config is disabled, this file is regenerated on every restart.

# Upstream DNS servers
upstreams:
  groups:
    default:
    {{- range .upstream_dns }}
      - {{ . }}
    {{- end }}

# Bootstrap DNS servers (used to resolve DoH/DoT upstream hostnames)
{{- if .bootstrap_dns }}
bootstrapDns:
{{- range .bootstrap_dns }}
  - upstream: {{ . }}
{{- end }}
{{- end }}

# DNS Blocking
{{- if .deny_lists }}
blocking:
  denylists:
  {{- range .deny_lists }}
    {{ .group }}:
    {{- range .entries }}
      - {{ . }}
    {{- end }}
  {{- end }}
  clientGroupsBlock:
  {{- range .client_groups_block }}
    {{ .client }}:
    {{- range .groups }}
      - {{ . }}
    {{- end }}
  {{- end }}
{{- end }}

# Conditional DNS Resolution
{{- if and .conditional_mapping (gt (len .conditional_mapping) 0) }}
conditional:
  mapping:
{{- range .conditional_mapping }}
{{- $domain := .domain }}
{{- $resolvers := .resolvers }}
{{- if and $domain (gt (len $resolvers) 0) }}
    {{ $domain }}:{{- range $idx, $resolver := $resolvers }}{{- if eq $idx 0 }} {{ $resolver }}{{ else }},{{ $resolver }}{{ end }}{{- end }}
{{- end }}
{{- end }}
{{- end }}

# Client Name Lookup
{{- if .client_lookup_upstream }}
clientLookup:
  upstream: {{ .client_lookup_upstream }}
{{- end }}

# DNS Caching
caching:
  minTime: {{ .caching.min_time }}
  maxTime: {{ .caching.max_time }}
  prefetching: {{ .caching.prefetching }}

ports:
  http:
    - 4000
