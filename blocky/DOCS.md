# Blocky Add-on Documentation

This document provides detailed configuration reference and advanced usage examples for the Blocky Home Assistant Add-on. For installation instructions and basic usage, see [README.md](README.md).

## Configuration Reference

### Upstream DNS Servers

Configure external DNS resolvers that Blocky queries after checking blocks and cache.

- **Groups**: Organize resolvers into named groups (e.g., `default`, `cloudflare`, `google`)
- **Resolvers**: DNS server addresses in various formats:
  - Standard DNS: `1.1.1.1` or `tcp+udp:8.8.8.8:53`
  - DNS-over-TLS: `tcp-tls:one.one.one.one`
  - DNS-over-HTTPS: `https://cloudflare-dns.com/dns-query`
- **Strategy**: Query distribution method
  - `parallel_best` (default): Queries 2 random resolvers, returns fastest
  - `random`: Queries single random resolver (better privacy)
  - `strict`: Queries resolvers sequentially in order
- **Timeout**: Max wait time for upstream response (default: `2s`)

### Bootstrap DNS

Required when upstream DNS uses hostnames (e.g., `tcp-tls:dns.google`). Bootstrap resolvers are simple IP-based DNS servers that resolve those hostnames, breaking the circular dependency.

**Example:**
```yaml
bootstrap:
  dns:
    - upstream: 1.1.1.1
    - upstream: 8.8.8.8
```

### Blocking & Allowlists

Configure domain blocking with denylists and exceptions.

- **Denylists**: Named groups of blocklist sources (URLs or local files)
- **Allowlists**: Domains to unblock (whitelist exceptions)
- **Client Groups**: Assign which lists apply to which clients
- **Block Type**:
  - `zeroIp` (default): Returns 0.0.0.0 (IPv4) or :: (IPv6)
  - `nxDomain`: Returns NXDOMAIN (domain doesn't exist)
- **Block TTL**: How long clients cache blocked responses (default: `6h`)

**Default lists include StevenBlack hosts, Disconnect.me ads & tracking.**

### Custom DNS

Define local hostname-to-IP mappings without forwarding to upstream DNS. Blocky acts as authoritative DNS server for these entries.

**Features:**
- Static IP assignments for local devices
- Automatic reverse DNS (PTR records)
- Subdomain resolution (any.prefix.hostname resolves to hostname's IP)
- CNAME support (specify hostname instead of IP)

**Example:**
```yaml
custom_dns:
  mapping:
    - hostname: nas.lan
      ips: 192.168.1.100
    - hostname: printer.lan
      ips: 192.168.1.101
  custom_ttl: 1h
```

### Conditional DNS

Route specific domains to designated DNS servers (split-DNS). Unlike Custom DNS which provides direct answers, Conditional DNS forwards queries to another resolver.

**Use cases:**
- Router DHCP hostnames (e.g., `*.fritz.box` → router DNS)
- Corporate VPN domains (e.g., `*.company.internal` → VPN DNS)
- Reverse DNS lookups (e.g., `192.168.1.in-addr.arpa` → router)

**Special domain `.` matches all unqualified hostnames** (single-word names like `nas` or `printer`).

**Example:**
```yaml
conditional:
  mapping:
    - domain: fritz.box
      resolvers:
        - 192.168.178.1
    - domain: "."
      resolvers:
        - 192.168.1.1
```

### Caching

DNS response caching reduces upstream queries and improves performance.

- **Min/Max Time**: Override upstream TTL values (leave empty to respect upstream)
- **Prefetching**: Automatically refresh popular domains before TTL expires
- **Prefetch Threshold**: Minimum queries (within tracking window) to enable prefetch (default: 5)
- **Max Items**: Limit total cached entries (0 = unlimited)
- **Negative Cache Time**: Cache NXDOMAIN responses (default: `30m`, set `-1` to disable)
- **Exclude**: Regex patterns to exclude from cache (e.g., `/.*\.lan$/` for local domains)

### Query Logging

Record DNS queries to various backends. **WARNING:** Logs contain sensitive network activity.

**Log Types:**
- `none` (default): Disabled
- `csv`: Daily rotating CSV files
- `csv-client`: Separate CSV per client
- `console`: Output to add-on logs
- `mysql`, `postgresql`, `timescale`: External databases

**Configuration:**
- **Target**: Directory for CSV files (e.g., `/config/query_logs`)
- **Database**: Host, port, username, password, database name
- **Fields**: Limit logged data (clientIP, clientName, responseReason, responseAnswer, question, duration)
- **Retention**: Auto-delete logs older than X days (0 = keep forever)
- **Flush Interval**: Batch write frequency (default: `30s`)

### Redis Integration

Synchronize cache and blocking state across multiple Blocky instances.

- **Address**: Redis server endpoint (hostname:port or IP:port)
- **Username/Password**: Authentication credentials (optional)
- **Database**: Redis database number (0-15, default: 0)
- **Required**: Fail startup if Redis unavailable (default: false)

### Prometheus Metrics

Enable monitoring endpoint at `http://[HOST]:4000/metrics`. Exposes DNS query statistics, cache performance, and blocking activity.

### Client Lookup

Resolve client IP addresses to friendly names using reverse DNS and static mappings.

**Configuration:**
- **Upstream**: DNS server for reverse lookups (usually router IP)
- **Clients**: Static name-to-IP mappings

### Logging

- **Level**: `trace`, `debug`, `info` (default), `warn`, `error`
- **Privacy Mode**: Obfuscate domains and IPs in logs with asterisks

### Custom Config Mode

Enable to use manual YAML configuration at `/addon_config/<repository>_blocky/config.yml`. All UI settings are ignored when enabled. Use for advanced Blocky features not available in UI (regex patterns, per-client rules, etc.).

## Configuration Examples

### Basic Home Network Setup

**Goal:** Network-wide ad blocking with fast DNS resolution

```yaml
upstreams:
  groups:
    - name: default
      resolvers:
        - tcp-tls:one.one.one.one
        - tcp-tls:dns.google
  strategy: parallel_best
  timeout: 2s

blocking:
  denylists:
    - name: ads
      sources:
        - https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
  client_groups_block:
    - name: default
      lists:
        - ads
  block_type: zeroIp

caching:
  prefetching: true
  prefetch_threshold: 5
```

### Split-DNS for Local Domains

**Goal:** Route router domains to router DNS, everything else to Cloudflare

```yaml
upstreams:
  groups:
    - name: default
      resolvers:
        - https://cloudflare-dns.com/dns-query

conditional:
  mapping:
    - domain: fritz.box
      resolvers:
        - 192.168.178.1
    - domain: "."  # Unqualified hostnames
      resolvers:
        - 192.168.178.1

custom_dns:
  mapping:
    - hostname: homeassistant.lan
      ips: 192.168.1.50
    - hostname: nas.lan
      ips: 192.168.1.100
```

### Home Assistant Automation Example

Control blocking via API from Home Assistant automations:

```yaml
# automation.yaml
- alias: "Disable DNS blocking for 1 hour"
  trigger:
    platform: state
    entity_id: input_boolean.allow_all_dns
    to: "on"
  action:
    - service: rest_command.disable_blocky
      data:
        duration: "3600s"

# configuration.yaml
rest_command:
  disable_blocky:
    url: "http://localhost:4000/api/blocking/disable"
    method: GET
    payload: "duration={{ duration }}"
  enable_blocky:
    url: "http://localhost:4000/api/blocking/enable"
    method: GET
```

### Database Query Logging

**Goal:** Log all queries to MySQL for analysis

```yaml
query_log:
  type: mysql
  db_host: 192.168.1.150
  db_port: 3306
  db_username: blocky_user
  db_password: !secret mysql_password
  db_database: blocky_logs
  log_retention_days: 30
  fields:
    - clientIP
    - clientName
    - question
    - responseAnswer
```

## HTTP API Reference

Access API at `http://[HOST]:4000/api/`

| Endpoint | Method | Parameters | Description |
|----------|--------|------------|-------------|
| `/blocking/status` | GET | - | Check if blocking is enabled |
| `/blocking/enable` | GET | - | Enable blocking |
| `/blocking/disable` | GET | `duration` (optional) | Disable blocking for duration (e.g., `30s`, `5m`, `1h`) |
| `/query` | GET | `query`, `type` | Test DNS resolution for domain |
| `/lists/refresh` | POST | - | Reload blocklists from sources |

**Examples:**
```bash
# Check status
curl http://homeassistant.local:4000/api/blocking/status

# Disable for 5 minutes
curl "http://homeassistant.local:4000/api/blocking/disable?duration=5m"

# Test resolution
curl "http://homeassistant.local:4000/api/query?query=example.com&type=A"
```

## Performance Tuning

**Low-memory devices (Raspberry Pi):**
- Reduce blocklist count
- Set `max_items_count: 5000` for cache
- Disable query logging
- Disable prefetching

**High-performance networks:**
- Enable prefetching with higher threshold
- Use `parallel_best` strategy
- Increase cache limits
- Use Redis for multi-instance deployments

**Privacy-focused:**
- Use `random` upstream strategy
- Enable log privacy mode
- Disable query logging
- Use DoH/DoT upstreams exclusively

## Troubleshooting

### Verify Configuration

In custom config mode, validate configuration before starting:
```bash
docker exec <container> blocky --config /etc/blocky/config.yml validate
```

### Check Blocklist Loading

Monitor add-on logs during startup for blocklist download status and entry counts.

### Test DNS Resolution

```bash
# Test from another machine
nslookup example.com <home-assistant-ip>

# Test blocked domain
nslookup ads.example.com <home-assistant-ip>
```

### Port 53 Already in Use (systemd-resolved)

On Linux systems (including some Home Assistant Supervised installations), `systemd-resolved` may already be listening on port 53, preventing Blocky from starting.

**Check if port 53 is in use:**
```bash
ss -tulnp | grep :53
# or
sudo lsof -i :53
```

**Option 1: Disable systemd-resolved entirely**
```bash
sudo systemctl disable systemd-resolved
sudo systemctl stop systemd-resolved
```
After disabling, update `/etc/resolv.conf` to point to a working DNS server (e.g., `nameserver 1.1.1.1`).

**Option 2: Disable only the DNS stub listener**
```bash
# Edit /etc/systemd/resolved.conf
sudo sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf
sudo systemctl restart systemd-resolved
```

**Home Assistant OS:** This is generally not an issue, as systemd-resolved is not running on Home Assistant OS.

### Debug Logging

Set log level to `debug` or `trace` for detailed diagnostics. Check logs for upstream connection errors, blocklist issues, or query processing problems.

## Support

- **Blocky Official Docs:** https://0xerr0r.github.io/blocky/
- **Blocky Configuration Reference:** https://0xerr0r.github.io/blocky/latest/configuration/
- **Add-on Issues:** Open issue in this repository
- **Home Assistant Community:** https://community.home-assistant.io/

## License

This add-on is distributed under the MIT License. See [LICENSE](LICENSE) file for details.

Blocky itself is licensed under Apache License 2.0 by [0xERR0R](https://github.com/0xERR0R/blocky).
