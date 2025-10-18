# Blocky Configuration Template
# This template dynamically generates the Blocky configuration based on user inputs.

## Upstream DNS Resolvers Configuration
upstream:
  default:
  {{- range .defaultUpstreamResolvers }}
    - {{ . }}
  {{- end }}

## Bootstrap DNS Servers
# Used for resolving upstream DoH and DoT servers by hostname and blacklist URLs.
bootstrapDns:
{{- range .bootstrapDns }}
{{- if .upstream }}
  - upstream: {{ .upstream }}
  {{- if .ips }}
    ips:
    {{- range .ips }}
      - {{ . }}
    {{- end }}
  {{- end }}
{{- end }}
{{- end }}

## Conditional DNS Mapping
# Redirect DNS queries for specific domains to designated DNS resolvers.
conditional:
  mapping:
  {{- range .conditionalMapping }}
    {{ .domain }}: {{ .ip }}
  {{- end }}

## Client Lookup Configuration
# Defines the upstream DNS server for reverse DNS lookups, typically the router.
clientLookup:
  upstream: tcp+udp:{{ .router }}

## Blocking Configuration
# Configures blacklists and blocking groups per client.
blocking:
  blackLists:
  {{- range .blackLists }}
    {{ .group }}:
    {{- range .entries }}
      - {{ . }}
    {{- end }}
  {{- end }}

  clientGroupsBlock:
  {{- range .clientGroupsBlock }}
    {{ .client }}:
    {{- range .groups }}
      - {{ . }}
    {{- end }}
  {{- end }}

## Caching Configuration
caching:
  minTime: {{ .caching.minTime }}
  maxTime: {{ .caching.maxTime }}
  maxItemsCount: {{ .caching.maxItemsCount }}
  prefetching: {{ .caching.prefetching }}
  prefetchExpires: {{ .caching.prefetchExpires }}
  prefetchThreshold: {{ .caching.prefetchThreshold }}
  prefetchMaxItemsCount: {{ .caching.prefetchMaxItemsCount }}
  cacheTimeNegative: {{ .caching.cacheTimeNegative }}

## Prometheus Metrics Configuration
{{- if .prometheus.enabled }}
# Enable HTTP listener for Prometheus metrics endpoint
port: {{ .prometheus.port }}

# Prometheus metrics endpoint configuration
prometheus:
  enable: true
  path: {{ .prometheus.path }}
{{- end }}
