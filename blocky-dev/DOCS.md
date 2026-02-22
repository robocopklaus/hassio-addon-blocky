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
- **Init Strategy**:
  - `blocking` (default): startup waits for upstream initialization
  - `failOnError`: startup fails if initialization fails
  - `fast`: startup continues while upstream checks run in background
- **Verify Upstreams on Start** (`start_verify`): if enabled, Blocky refuses startup when no upstream is reachable.

If your WAN link is unreliable, consider `init_strategy: fast` to avoid startup stalls and enable `start_verify` only when strict startup guarantees are desired.

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

### EDNS Client Subnet (ECS)

Optional ECS forwarding controls for upstream DNS requests.

- **use_as_client**: sends client subnet information to upstreams when available
- **forward**: forwards ECS received from downstream clients

ECS can improve CDN localization but may reduce privacy by sharing network location hints.

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
- **Target**: Directory for CSV files (e.g., `/config/query_logs`) when `type` is `csv` or `csv-client`
- **Database**: Host, port, username, password, database name
- **Fields**: Limit logged data (clientIP, clientName, responseReason, responseAnswer, question, duration)
- **Retention**: Auto-delete logs older than X days (0 = keep forever)
- **Flush Interval**: Batch write frequency (default: `30s`)

Path note: `/config/...` is the container path. On the Home Assistant host, the same files are accessible under `/addon_config/<repository>_blocky/...`.

For `mysql`, `postgresql`, and `timescale` types, Blocky constructs the target connection string from `db_*` fields; `target` is not used directly.

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
- **Privacy Mode**: Obfuscate domains and IPs in logs with asterisks (enabled by default). Disable only when full domain visibility is needed for debugging. Note that even with privacy mode enabled, query metadata (timing, frequency, response types) may still reveal browsing patterns.

### Custom Config Mode

Enable to use manual YAML configuration at `/addon_config/<repository>_blocky/config.yml`.

**Important:** when enabled, all UI settings are ignored. The UI remains visible due to Home Assistant limitations, but values there are not applied. Treat UI fields as read-only in this mode.

Use this mode for advanced Blocky features not available in UI (regex patterns, per-client rules, etc.).

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

> **Security warning:** Blocky's API is unauthenticated. Any host with network access to port 4000 can call control endpoints. Keep the API on trusted LAN segments only.

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

**Memory guidance:**
- Absolute minimum: ~256MB for lightweight setups
- Recommended: 512MB+ for larger blocklists, query logging, or aggressive caching

**Low-memory devices (Raspberry Pi):**
- Reduce blocklist count
- Set `max_items_count: 5000` for cache
- Disable query logging
- Disable prefetching

Home Assistant add-ons do not expose per-add-on CPU/RAM limits in this project today. Use Blocky cache and logging settings to control memory footprint.

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

## Security

### Container Privileges

The add-on currently runs as root inside the HA add-on sandbox because DNS binds to privileged port 53. This is common for DNS add-ons, but still a tradeoff.

- Prefer strict network boundaries (LAN-only access)
- Keep host and add-on updated
- Avoid exposing DNS/API ports to untrusted networks

### DNS Amplification Prevention

This add-on exposes port 53 (TCP and UDP) for DNS resolution. While Home Assistant's container network typically provides LAN isolation, misconfigured routers or firewall rules can accidentally expose port 53 to the internet, turning Blocky into an **open DNS resolver**.

**What is a DNS amplification attack?**

DNS amplification is a type of DDoS attack where an attacker sends small DNS queries with a spoofed source IP to an open resolver. The resolver sends much larger responses to the victim's IP address, amplifying the attack traffic. A single misconfigured resolver can generate significant attack bandwidth.

**How to protect yourself:**

1. **Router firewall rules** — Block all inbound DNS traffic (port 53 TCP/UDP) from your WAN interface. Most consumer routers do this by default, but verify your configuration:
   ```
   # Example: iptables rule to block external DNS access
   iptables -A INPUT -i eth0 -p udp --dport 53 -j DROP
   iptables -A INPUT -i eth0 -p tcp --dport 53 -j DROP
   ```
   Replace `eth0` with your WAN interface name.

2. **No port forwarding** — Never create port forwarding rules for port 53 to your Home Assistant host. DNS resolution should only be available on your local network.

3. **VPN for remote access** — If you need DNS resolution remotely, use a VPN to connect to your home network rather than exposing port 53 directly.

4. **Verify your configuration** — Use an external open resolver test to confirm port 53 is not reachable from the internet:
   - [Open Resolver Project](https://openresolver.com/) — Tests if your IP is an open resolver
   - From an external network: `nslookup example.com <your-public-ip>` — should timeout or be refused

5. **Monitor DNS traffic** — Enable query logging temporarily to check for unexpected query patterns (high volumes, queries from unknown IPs) that may indicate your resolver is being abused.

**Note:** Home Assistant's Docker network architecture provides a layer of isolation, and the add-on's port mappings are typically only accessible from the local network. However, network configurations vary, and it is your responsibility to ensure port 53 is not exposed to the internet.

## Troubleshooting

### Port 53 conflict (systemd-resolved)

On some Linux hosts (especially Home Assistant Supervised), `systemd-resolved` may bind to port 53.

```bash
ss -tulnp | grep :53
```

If needed, set `DNSStubListener=no` in `/etc/systemd/resolved.conf`, restart `systemd-resolved`, then restart the add-on.

### Upstreams unreachable at startup

If all upstream resolvers are unreachable, startup behavior depends on upstream init settings.

- `init_strategy: blocking` can delay readiness while checks run
- `init_strategy: fast` starts DNS sooner and resolves upstream availability in background
- `start_verify: true` fails startup when no upstream is reachable

Use `fast` for unstable WAN links and verify behavior in your environment.

### Blocklist source freshness

Default blocklists are curated for reliability. The `sysctl.org/cameleon` source was removed because maintenance status could not be confirmed.

If custom sources stop updating, Blocky logs refresh warnings. Replace stale lists with maintained alternatives.

### Ingress note

Ingress is not enabled by default because Blocky provides an API rather than a dedicated web UI. For authenticated remote usage, prefer Home Assistant proxying/reverse proxy with auth, or VPN access.

## Upgrade and Migration Strategy

### Standard mode (UI-driven)

Schema migrations are handled by template/config updates shipped with the add-on. Upgrading the add-on updates generated config on restart.

### Custom config mode

You are responsible for adapting `/addon_config/<repository>_blocky/config.yml` when upstream Blocky schema changes.

Recommended process:

1. Read `blocky/CHANGELOG.md` and upstream Blocky release notes before upgrading
2. Compare your custom config against the latest generated template output
3. Validate manually with `blocky validate --config /etc/blocky/config.yml`
4. Keep a backup of the last known-good custom config for rollback

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
