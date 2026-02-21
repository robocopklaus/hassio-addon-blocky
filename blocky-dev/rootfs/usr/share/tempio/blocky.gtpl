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
    {{ .name | quote }}:
{{- range .resolvers }}
      - {{ . | quote }}
{{- end }}
{{- end }}
{{- if .upstreams.init_strategy }}
  init:
    strategy: {{ .upstreams.init_strategy | quote }}
{{- end }}
{{- if .upstreams.strategy }}
  strategy: {{ .upstreams.strategy | quote }}
{{- end }}
{{- if .upstreams.timeout }}
  timeout: {{ .upstreams.timeout | quote }}
{{- end }}
{{- if .upstreams.user_agent }}
  userAgent: {{ .upstreams.user_agent | quote }}
{{- end }}


{{- if .bootstrap.dns }}
# Bootstrap DNS
bootstrapDns:
{{- range .bootstrap.dns }}
  - upstream: {{ .upstream | quote }}
{{- if .ips }}
    ips:
{{- range .ips }}
      - {{ . | quote }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{- if .filtering.query_types }}
# Query Type Filtering
filtering:
  queryTypes:
{{- range .filtering.query_types }}
    - {{ . | quote }}
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
  customTTL: {{ .custom_dns.custom_ttl | quote }}
  filterUnmappedTypes: {{ .custom_dns.filter_unmapped_types }}
{{- if .custom_dns.rewrite }}
  rewrite:
{{- range .custom_dns.rewrite }}
    {{ .source | quote }}: {{ .target | quote }}
{{- end }}
{{- end }}
{{- if .custom_dns.mapping }}
  mapping:
{{- range .custom_dns.mapping }}
    {{ .hostname | quote }}: {{ .ips | quote }}
{{- end }}
{{- end }}
{{- end }}

{{- if or .conditional.mapping .conditional.rewrite .conditional.fallback_upstream }}
# Conditional DNS Resolution
conditional:
{{- if .conditional.rewrite }}
  rewrite:
{{- range .conditional.rewrite }}
    {{ .source | quote }}: {{ .target | quote }}
{{- end }}
{{- end }}
{{- if .conditional.mapping }}
  mapping:
{{- range .conditional.mapping }}
    {{ .domain | quote }}: "{{ range $index, $resolver := .resolvers }}{{if $index}},{{end}}{{ $resolver | replace `\` `\\` | replace `"` `\"` }}{{end}}"
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
  upstream: {{ $upstream | quote }}
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
    {{ $entry.name | quote }}:
{{- range $address := $entry.addresses }}
      - {{ $address | quote }}
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
    {{ $list.name | quote }}:
{{- range $source := $list.sources }}
      - {{ $source | quote }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- if $allowlists }}
  allowlists:
{{- range $list := $allowlists }}
{{- if and $list.name $list.sources }}
    {{ $list.name | quote }}:
{{- range $source := $list.sources }}
      - {{ $source | quote }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- if $clientGroups }}
  clientGroupsBlock:
{{- range $group := $clientGroups }}
{{- if and $group.name $group.lists }}
    {{ $group.name | quote }}:
{{- range $listName := $group.lists }}
      - {{ $listName | quote }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- if $blocking.block_type }}
  blockType: {{ $blocking.block_type | quote }}
{{- end }}
{{- if $blocking.block_ttl }}
  blockTTL: {{ $blocking.block_ttl | quote }}
{{- end }}
{{- end }}
{{- end }}


{{- $caching := .caching }}
{{- if or $caching.min_time $caching.max_time $caching.prefetching $caching.cache_time_negative $caching.max_items_count $caching.prefetch_expires $caching.prefetch_threshold $caching.prefetch_max_items_count $caching.exclude }}
# DNS Caching
caching:
{{- if $caching.min_time }}
  minTime: {{ $caching.min_time | quote }}
{{- end }}
{{- if $caching.max_time }}
  maxTime: {{ $caching.max_time | quote }}
{{- end }}
{{- if $caching.max_items_count }}
  maxItemsCount: {{ $caching.max_items_count }}
{{- end }}
{{- if $caching.prefetching }}
  prefetching: {{ $caching.prefetching }}
{{- end }}
{{- if $caching.prefetch_expires }}
  prefetchExpires: {{ $caching.prefetch_expires | quote }}
{{- end }}
{{- if $caching.prefetch_threshold }}
  prefetchThreshold: {{ $caching.prefetch_threshold }}
{{- end }}
{{- if $caching.prefetch_max_items_count }}
  prefetchMaxItemsCount: {{ $caching.prefetch_max_items_count }}
{{- end }}
{{- if $caching.cache_time_negative }}
  cacheTimeNegative: {{ $caching.cache_time_negative | quote }}
{{- end }}
{{- if $caching.exclude }}
  exclude:
{{- range $caching.exclude }}
    - {{ . | quote }}
{{- end }}
{{- end }}
{{- end }}

{{- $redis := .redis }}
{{- if $redis.address }}
# Redis Integration
redis:
  address: {{ $redis.address | quote }}
{{- if $redis.username }}
  username: {{ $redis.username | quote }}
{{- end }}
{{- if $redis.password }}
  password: {{ $redis.password | quote }}
{{- end }}
  database: {{ $redis.database }}
  required: {{ $redis.required }}
  connectionAttempts: {{ $redis.connection_attempts }}
  connectionCooldown: {{ $redis.connection_cooldown | quote }}
{{- end }}

{{- if .prometheus.enable }}
# Prometheus Metrics
prometheus:
  enable: {{ .prometheus.enable }}
  path: {{ .prometheus.path | quote }}
{{- end }}


{{- $queryLog := .query_log }}
{{- if $queryLog.type }}
# Query Logging
queryLog:
  type: {{ $queryLog.type | quote }}
{{- if or (eq $queryLog.type "csv") (eq $queryLog.type "csv-client") }}
{{- if $queryLog.target }}
  target: {{ $queryLog.target | quote }}
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
  target: "{{ if $queryLog.db_username }}{{ $queryLog.db_username | replace `\` `\\` | replace `"` `\"` }}{{ if $queryLog.db_password }}:{{ $queryLog.db_password | replace `\` `\\` | replace `"` `\"` }}{{ end }}@{{ end }}tcp({{ $queryLog.db_host | replace `\` `\\` | replace `"` `\"` }}:{{ $port }})/{{ $queryLog.db_database | replace `\` `\\` | replace `"` `\"` }}?charset=utf8mb4&parseTime=True"
{{- else }}
  target: "postgres://{{ if $queryLog.db_username }}{{ urlquery $queryLog.db_username | replace "+" "%20" }}{{ if $queryLog.db_password }}:{{ urlquery $queryLog.db_password | replace "+" "%20" }}{{ end }}@{{ end }}{{ $queryLog.db_host | replace `\` `\\` | replace `"` `\"` }}:{{ $port }}/{{ $queryLog.db_database | replace `\` `\\` | replace `"` `\"` }}"
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
  creationCooldown: {{ $queryLog.creation_cooldown | quote }}
{{- end }}
{{- if $queryLog.fields }}
  fields:
{{- range $queryLog.fields }}
    - {{ . | quote }}
{{- end }}
{{- end }}
{{- if $queryLog.flush_interval }}
  flushInterval: {{ $queryLog.flush_interval | quote }}
{{- end }}
{{- end }}

# Ports & Addresses
ports:
  http:
    - 4000 # Hardcoded since this is the internal Docker port

# Logging
log:
  level: {{ .log.level | quote }}
  timestamp: {{ .log.timestamp }}
  privacy: {{ .log.privacy }}
