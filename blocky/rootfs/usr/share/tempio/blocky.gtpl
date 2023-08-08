---
upstream:
  default:
  {{ range .defaultUpstreamResolvers }}
    - {{ . }}
  {{ end }}

bootstrapDns:
{{ range .bootstrapDns }}
{{ if .upstream }}
  - upstream: {{ .upstream }}
  {{ if .ips }}
    ips:
    {{ range .ips }}
      - {{ . }}
    {{ end }}
  {{ end }}
{{ end }}
{{ end }}

conditional:
  mapping:
  {{ range .conditionalMapping }}
    {{ .domain }}: {{ .ip }}
  {{ end }}

clientLookup:
  upstream: {{ .router }}
blocking:
  blackLists:
  {{ range .blackLists }}
    {{ .group }}:
    {{ range .entries }}
      - {{ . }}
    {{ end }}
  {{ end }}

  clientGroupsBlock:
  {{ range .clientGroupsBlock }}
    {{ .client }}:
    {{ range .groups }}
      - {{ . }}
    {{ end }}
  {{ end }}