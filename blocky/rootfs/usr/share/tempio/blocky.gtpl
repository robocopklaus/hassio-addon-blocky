# Blocky Configuration
# Generated from Home Assistant add-on options
# Reference: https://0xerr0r.github.io/blocky/latest/configuration/
#
# IMPORTANT: To edit this file directly, enable "Custom Configuration" in the add-on UI.
# When custom config is disabled, this file is regenerated on every restart.

# Upstream DNS Servers
upstreams:
{{- if .upstreams.init_strategy }}
  init:
    strategy: {{ .upstreams.init_strategy }}
{{- end }}
  groups:
{{- range .upstreams.groups }}
    {{ .name }}:
{{- range .resolvers }}
      - {{ . }}
{{- end }}
{{- end }}
{{- if .upstreams.strategy }}
  strategy: {{ .upstreams.strategy }}
{{- end }}
{{- if .upstreams.timeout }}
  timeout: {{ .upstreams.timeout }}
{{- end }}
{{- if .upstreams.user_agent }}
  userAgent: {{ .upstreams.user_agent }}
{{- end }}
{{- if .bootstrap.dns }}

# Bootstrap DNS
bootstrapDns:
{{- range .bootstrap.dns }}
  - upstream: {{ . }}
{{- end }}
{{- end }}

{{- if or .custom_dns.mapping .custom_dns.rewrite }}

# Custom DNS
customDNS:
  customTTL: {{ .custom_dns.custom_ttl }}
  filterUnmappedTypes: {{ .custom_dns.filter_unmapped_types }}
{{- if .custom_dns.rewrite }}
  rewrite:
{{- range .custom_dns.rewrite }}
    {{ .source }}: {{ .target }}
{{- end }}
{{- end }}
{{- if .custom_dns.mapping }}
  mapping:
{{- range .custom_dns.mapping }}
    {{ .hostname }}: {{ .ips }}
{{- end }}
{{- end }}
{{- end }}

{{- $blocking := .blocking }}
{{- if $blocking }}
{{- $denylists := $blocking.denylists }}
{{- $allowlists := $blocking.allowlists }}
{{- $clientGroups := $blocking.client_groups_block }}
{{- if or $denylists $allowlists $clientGroups }}

# Blocking & Allowlists
blocking:
{{- if $denylists }}
  denylists:
{{- range $list := $denylists }}
{{- if and $list.name $list.sources }}
    {{ $list.name }}:
{{- range $source := $list.sources }}
      - {{ $source }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- if $allowlists }}
  allowlists:
{{- range $list := $allowlists }}
{{- if and $list.name $list.sources }}
    {{ $list.name }}:
{{- range $source := $list.sources }}
      - {{ $source }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- if $clientGroups }}
  clientGroupsBlock:
{{- range $group := $clientGroups }}
{{- if and $group.name $group.lists }}
    {{ $group.name }}:
{{- range $listName := $group.lists }}
      - {{ $listName }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- if $blocking.block_type }}
  blockType: {{ $blocking.block_type }}
{{- end }}
{{- if $blocking.block_ttl }}
  blockTTL: {{ $blocking.block_ttl }}
{{- end }}
{{- end }}
{{- end }}
{{- if or .conditional.mapping .conditional.rewrite .conditional.fallback_upstream }}

# Conditional DNS Resolution
conditional:
{{- if .conditional.rewrite }}
  rewrite:
{{- range .conditional.rewrite }}
    {{ .source }}: {{ .target }}
{{- end }}
{{- end }}
{{- if .conditional.mapping }}
  mapping:
{{- range .conditional.mapping }}
    {{ .domain }}: {{ range $index, $resolver := .resolvers }}{{if $index}},{{end}}{{ $resolver }}{{end}}
{{- end }}
{{- end }}
{{- if .conditional.fallback_upstream }}
  fallbackUpstream: {{ .conditional.fallback_upstream }}
{{- end }}
{{- end }}

{{- $clientLookup := .client_lookup }}
{{- if $clientLookup }}
{{- $upstream := $clientLookup.upstream }}
{{- $singleOrder := $clientLookup.single_name_order }}
{{- $clients := $clientLookup.clients }}
{{- if or $upstream $singleOrder $clients }}

# Client Name Lookup
clientLookup:
{{- if $upstream }}
  upstream: {{ $upstream }}
{{- end }}
{{- if $singleOrder }}
  singleNameOrder:
{{- range $order := $singleOrder }}
    - {{ $order }}
{{- end }}
{{- end }}
{{- if $clients }}
  clients:
{{- range $entry := $clients }}
{{- if and $entry.name $entry.addresses }}
    {{ $entry.name }}:
{{- range $address := $entry.addresses }}
      - {{ $address }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- if .filtering.query_types }}

# Query Type Filtering
filtering:
  queryTypes:
{{- range .filtering.query_types }}
    - {{ . }}
{{- end }}
{{- end }}
{{- if .fqdn_only.enable }}

# FQDN-Only Mode
fqdnOnly:
  enable: {{ .fqdn_only.enable }}
{{- end }}
{{- $caching := .caching }}
{{- if or $caching.min_time $caching.max_time $caching.prefetching $caching.cache_time_negative }}

# DNS Caching
caching:
{{- if $caching.min_time }}
  minTime: {{ $caching.min_time }}
{{- end }}
{{- if $caching.max_time }}
  maxTime: {{ $caching.max_time }}
{{- end }}
{{- if $caching.prefetching }}
  prefetching: {{ $caching.prefetching }}
{{- end }}
{{- if $caching.cache_time_negative }}
  cacheTimeNegative: {{ $caching.cache_time_negative }}
{{- end }}
{{- end }}
{{- $redis := .redis }}
{{- if $redis.address }}

# Redis Integration
redis:
  address: {{ $redis.address }}
{{- if $redis.username }}
  username: {{ $redis.username }}
{{- end }}
{{- if $redis.password }}
  password: {{ $redis.password }}
{{- end }}
  database: {{ $redis.database }}
  required: {{ $redis.required }}
  connectionAttempts: {{ $redis.connection_attempts }}
  connectionCooldown: {{ $redis.connection_cooldown }}
{{- end }}
{{- if .prometheus.enable }}

# Prometheus Metrics
prometheus:
  enable: {{ .prometheus.enable }}
  path: {{ .prometheus.path }}
{{- end }}

# Ports & Addresses
ports:
  http:
    - 4000 # Hardcoded since this is the internal Docker port

# Logging
log:
  level: {{ .log.level }}
  timestamp: {{ .log.timestamp }}
  privacy: {{ .log.privacy }}
