# Blocky Configuration
# Generated from Home Assistant add-on options
# Reference: https://0xerr0r.github.io/blocky/latest/configuration/
#
# IMPORTANT: To edit this file directly, enable "Custom Configuration" in the add-on UI.
# When custom config is disabled, this file is regenerated on every restart.

# Upstream DNS Servers
upstreams:
  groups:
{{- range .upstreams.groups }}
    {{ .name }}:
{{- range .resolvers }}
      - {{ . }}
{{- end }}
{{- end }}
{{- if .upstreams.init_strategy }}
  init:
    strategy: {{ .upstreams.init_strategy }}
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
  - upstream: {{ .upstream }}
{{- if .ips }}
    ips:
{{- range .ips }}
      - {{ . }}
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


{{- $caching := .caching }}
{{- if or $caching.min_time $caching.max_time $caching.prefetching $caching.cache_time_negative $caching.max_items_count $caching.prefetch_expires $caching.prefetch_threshold $caching.prefetch_max_items_count $caching.exclude }}
# DNS Caching
caching:
{{- if $caching.min_time }}
  minTime: {{ $caching.min_time }}
{{- end }}
{{- if $caching.max_time }}
  maxTime: {{ $caching.max_time }}
{{- end }}
{{- if $caching.max_items_count }}
  maxItemsCount: {{ $caching.max_items_count }}
{{- end }}
{{- if $caching.prefetching }}
  prefetching: {{ $caching.prefetching }}
{{- end }}
{{- if $caching.prefetch_expires }}
  prefetchExpires: {{ $caching.prefetch_expires }}
{{- end }}
{{- if $caching.prefetch_threshold }}
  prefetchThreshold: {{ $caching.prefetch_threshold }}
{{- end }}
{{- if $caching.prefetch_max_items_count }}
  prefetchMaxItemsCount: {{ $caching.prefetch_max_items_count }}
{{- end }}
{{- if $caching.cache_time_negative }}
  cacheTimeNegative: {{ $caching.cache_time_negative }}
{{- end }}
{{- if $caching.exclude }}
  exclude:
{{- range $caching.exclude }}
    - {{ . }}
{{- end }}
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


{{- $queryLog := .query_log }}
{{- if $queryLog.type }}
# Query Logging
queryLog:
  type: {{ $queryLog.type }}
{{- if or (eq $queryLog.type "csv") (eq $queryLog.type "csv-client") }}
{{- if $queryLog.target }}
  target: {{ $queryLog.target }}
{{- end }}
{{- end }}
{{- if or (eq $queryLog.type "mysql") (eq $queryLog.type "postgresql") (eq $queryLog.type "timescale") }}
{{- if and $queryLog.db_host $queryLog.db_database }}
{{- $port := $queryLog.db_port }}
{{- if eq $port 0 }}
{{- if eq $queryLog.type "mysql" }}
{{- $port = 3306 }}
{{- else }}
{{- $port = 5432 }}
{{- end }}
{{- end }}
{{- if eq $queryLog.type "mysql" }}
  target: {{ if $queryLog.db_username }}{{ $queryLog.db_username }}{{ if $queryLog.db_password }}:{{ $queryLog.db_password }}{{ end }}@{{ end }}tcp({{ $queryLog.db_host }}:{{ $port }})/{{ $queryLog.db_database }}?charset=utf8mb4&parseTime=True
{{- else }}
  target: postgres://{{ if $queryLog.db_username }}{{ $queryLog.db_username }}{{ if $queryLog.db_password }}:{{ $queryLog.db_password }}{{ end }}@{{ end }}{{ $queryLog.db_host }}:{{ $port }}/{{ $queryLog.db_database }}
{{- end }}
{{- end }}
{{- end }}
{{- if $queryLog.log_retention_days }}
  logRetentionDays: {{ $queryLog.log_retention_days }}
{{- end }}
{{- if $queryLog.creation_attempts }}
  creationAttempts: {{ $queryLog.creation_attempts }}
{{- end }}
{{- if $queryLog.creation_cooldown }}
  creationCooldown: {{ $queryLog.creation_cooldown }}
{{- end }}
{{- if $queryLog.fields }}
  fields:
{{- range $queryLog.fields }}
    - {{ . }}
{{- end }}
{{- end }}
{{- if $queryLog.flush_interval }}
  flushInterval: {{ $queryLog.flush_interval }}
{{- end }}
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
