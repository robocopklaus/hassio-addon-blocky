# Home Assistant Add-on: Blocky

## Introduction

Blocky is a fast and lightweight DNS proxy and ad-blocker designed for your home network. Unlike browser-based ad-blockers, Blocky works at the DNS level, blocking ads and trackers for all devices on your network without requiring software installation on each device.

### Key Benefits

- **Network-wide Protection**: Blocks ads and trackers for all connected devices (phones, tablets, smart TVs, IoT devices)
- **No UI Required**: Operates as a DNS service - no web interface to manage
- **Privacy-Focused**: Zero telemetry, no data collection, completely private
- **High Performance**: Efficient caching, prefetching, and low memory footprint
- **Modern DNS Protocols**: Supports DNS-over-HTTPS (DoH) and DNS-over-TLS (DoT)
- **Local Network Integration**: Resolve local hostnames (router, NAS, etc.) alongside internet DNS

### How It Works

1. Devices on your network send DNS queries to Blocky (port 53)
2. Blocky checks queries against configured block lists
3. Blocked domains return a null response (no connection made)
4. Allowed queries are forwarded to upstream DNS servers (Cloudflare, Google, etc.)
5. Responses are cached for improved performance

**Note**: This add-on has no web UI. Configuration is done through Home Assistant's add-on options. Metrics are available at `http://<host>:4000` when Prometheus is enabled.

---

## Installation

### 1. Add Repository to Home Assistant

1. Navigate to **Settings** → **Add-ons** → **Add-on Store**
2. Click the **⋮** menu (top right) → **Repositories**
3. Add this repository URL:
   ```
   https://github.com/robocopklaus/hassio-addon-blocky
   ```
4. Click **Add** → **Close**

### 2. Install the Add-on

1. Find **Blocky** in your add-on store
2. Click on the add-on
3. Click **Install**
4. Wait for installation to complete

### 3. Configure and Start

1. Go to the **Configuration** tab
2. Review and adjust options (see Configuration Overview below)
3. Click **Save**
4. Go to the **Info** tab
5. Click **Start**
6. Enable **Watchdog** (recommended) for automatic restart on failure

---

## Configuration Overview

This add-on provides essential configuration options through the Home Assistant UI. For detailed configuration information and all available options, see the [Blocky Configuration Reference](https://0xerr0r.github.io/blocky/latest/configuration/).

### Main Configuration Options

**Upstream DNS Servers** (`upstream_dns`)
- DNS resolvers that Blocky forwards queries to
- Supports plain DNS, DNS-over-TLS (DoT), and DNS-over-HTTPS (DoH)
- Default: Cloudflare and Google DoT/DoH servers
- [Full upstream docs →](https://0xerr0r.github.io/blocky/latest/configuration/#upstream)

**Bootstrap DNS** (`bootstrap_dns`)
- DNS servers used to resolve upstream DoH/DoT hostnames
- Must be plain IP addresses only
- Default: `1.1.1.1`, `8.8.8.8`
- [Full bootstrap docs →](https://0xerr0r.github.io/blocky/latest/configuration/#bootstrapdns)

**Custom DNS** (`custom_dns`)
- Define custom DNS responses for local domains
- Map hostnames to IP addresses (e.g., `printer.lan` → `192.168.1.100`)
- Supports CNAME, domain rewriting, and custom TTL
- [Full customDNS docs →](https://0xerr0r.github.io/blocky/latest/configuration/#custom-dns)

**Blocking** (`blocking`)
- Configure deny lists (block lists) and allow lists
- Pre-configured with StevenBlack hosts by default
- Assign different block lists to client groups
- [Full blocking docs →](https://0xerr0r.github.io/blocky/latest/configuration/#blocking)

**Conditional DNS** (`conditional`)
- Route specific domains to designated resolvers
- Essential for local network device resolution
- Example: Route `*.fritz.box` to router at `192.168.178.1`
- [Full conditional docs →](https://0xerr0r.github.io/blocky/latest/configuration/#conditional)

**Client Lookup** (`client_lookup`)
- Resolve client IP addresses to readable names using reverse DNS
- Helpful for metrics and logs
- [Full clientLookup docs →](https://0xerr0r.github.io/blocky/latest/configuration/#client-lookup)

**Caching** (`caching`)
- Configure DNS response caching behavior
- Options for min/max cache time and prefetching
- [Full caching docs →](https://0xerr0r.github.io/blocky/latest/configuration/#caching)

**Redis Integration** (`redis`)
- Synchronize cache across multiple Blocky instances
- Useful for distributed deployments only
- [Full redis docs →](https://0xerr0r.github.io/blocky/latest/configuration/#redis)

**Prometheus Metrics** (`prometheus`)
- Enable/disable Prometheus metrics endpoint
- Default: disabled (enable to access metrics at port 4000)
- [Full prometheus docs →](https://0xerr0r.github.io/blocky/latest/configuration/#prometheus)

**Logging** (`log`)
- Control log verbosity, timestamps, and privacy
- Levels: trace, debug, info, warn, error
- [Full logging docs →](https://0xerr0r.github.io/blocky/latest/configuration/#log)

**Query Type Filtering** (`filtering.query_types`)
- Drop specific DNS query types (e.g., AAAA for IPv6)
- Useful for forcing IPv4-only resolution
- [Full filtering docs →](https://0xerr0r.github.io/blocky/latest/configuration/#filtering)

**FQDN-Only Mode** (`fqdn_only`)
- Restrict resolution to fully qualified domain names only
- Blocks single-word hostnames (use with caution)
- [Full fqdnOnly docs →](https://0xerr0r.github.io/blocky/latest/configuration/#special-use-domains)

### Custom Configuration Mode (Advanced)

Enable `custom_config: true` to manually edit the Blocky configuration file and access all advanced features:

- Per-client custom blocking rules
- Query logging
- Advanced allowlists (regex, per-client)
- Response filtering
- And much more

**Configuration file location**: `/addon_config/<repository>_blocky/config.yml`

**Full feature documentation**: [Blocky Configuration Reference](https://0xerr0r.github.io/blocky/latest/configuration/)

⚠️ **Important**: When custom config mode is enabled, ALL Home Assistant UI options are ignored.

---

## Network Setup Guide

For Blocky to work, network devices must send DNS queries to Blocky (port 53). There are two approaches:

### Option 1: Router DHCP Configuration (Recommended)

Configure your router to advertise Blocky as the DNS server via DHCP. All devices automatically use Blocky without per-device configuration.

**Steps** (varies by router):
1. Access your router's admin interface
2. Find DHCP settings (often under LAN or Network settings)
3. Set **Primary DNS Server** to Home Assistant's IP address (e.g., `192.168.1.100`)
4. Optional: Set **Secondary DNS Server** to a fallback (e.g., `1.1.1.1`)
5. Save and reboot router
6. Reconnect devices or renew DHCP leases

**Common Router Interfaces**:
- **FritzBox**: Home Network → Network → Network Settings → DNS Server
- **Ubiquiti**: Settings → Networks → LAN → DHCP Name Server
- **pfSense**: Services → DHCP Server → DNS Servers
- **OpenWrt**: Network → Interfaces → LAN → DHCP Server → Advanced Settings

**Verification**:
```bash
# On a device, check DNS server
# macOS/Linux:
cat /etc/resolv.conf

# Windows:
ipconfig /all

# Should show Home Assistant's IP as DNS server
```

### Option 2: Manual Device Configuration

Configure DNS server on individual devices. Useful for testing or selective deployment.

**macOS**:
System Settings → Network → [Your Connection] → Details → DNS tab → Add (+) → Enter Home Assistant IP

**Windows**:
Control Panel → Network and Internet → Network Connections → Right-click connection → Properties → Internet Protocol Version 4 (TCP/IPv4) → Properties → Use the following DNS server addresses

**iOS/iPadOS**:
Settings → Wi-Fi → (i) next to network → Configure DNS → Manual → Add Server → Enter Home Assistant IP

**Android**:
Settings → Network & Internet → Wi-Fi → Long-press network → Modify network → Advanced options → IP settings → Static → DNS 1: Home Assistant IP

### Testing DNS

```bash
# Test from any device (replace 192.168.1.100 with HA IP)
nslookup example.com 192.168.1.100
dig @192.168.1.100 example.com

# Should return IP address without errors
```

---

## Common Use Cases

### 1. Basic Ad-Blocking Setup

Block ads and trackers network-wide with minimal configuration.

```yaml
blocking:
  denylists:
    - name: ads
      sources:
        - https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
  client_groups_block:
    - name: default
      lists:
        - ads
```

### 2. Local Network DNS Resolution

Access local devices by hostname (e.g., `http://nas.local`, `http://router.fritz.box`).

```yaml
conditional:
  mapping:
    - domain: "fritz.box"
      resolvers:
        - "192.168.178.1"  # Router IP
    - domain: "local"
      resolvers:
        - "192.168.1.1"  # Local DNS server
    - domain: "."  # Unqualified hostnames
      resolvers:
        - "192.168.1.1"
```

### 3. Custom Static DNS Entries

Assign static IP addresses to hostnames on your network.

```yaml
custom_dns:
  mapping:
    - hostname: printer.lan
      ips: 192.168.1.100
    - hostname: nas.local
      ips: 192.168.1.50
    - hostname: server.lan
      ips: 192.168.1.10,2001:db8:85a3::1  # Dual-stack IPv4 + IPv6
```

### 4. Per-Device Blocking Rules (Custom Config Mode)

Different blocking policies per device/client group. Requires custom config mode.

```yaml
# /addon_config/<repository>_blocky/config.yml
blocking:
  denylists:
    ads:
      - https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
    tracking:
      - https://s3.amazonaws.com/lists.disconnect.me/simple_tracking.txt
    social:
      - https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/social-only/hosts
  clientGroupsBlock:
    kids:
      - ads
      - tracking
      - social
    adults:
      - ads

clients:
  kids:
    - 192.168.1.100  # Kid's iPad
    - 192.168.1.101  # Kid's laptop
  adults:
    - 192.168.1.50
    - 192.168.1.51
```

---

## Monitoring

When Prometheus is enabled (`prometheus.enable: true`), Blocky exposes metrics at `http://<home-assistant-ip>:4000/metrics`.

**Available Metrics**:
- DNS query count (total, by type, by response)
- Blocked query count
- Cache hit/miss ratio
- Upstream response times

**Health Check**: `http://<home-assistant-ip>:4000/` returns JSON with Blocky status and version.

For query logging and advanced monitoring features, see the [Blocky documentation](https://0xerr0r.github.io/blocky/latest/configuration/#querylog).

---

## Support & Resources

### Documentation
- **Full Blocky Documentation**: [https://0xerr0r.github.io/blocky/](https://0xerr0r.github.io/blocky/)
- **Configuration Reference**: [https://0xerr0r.github.io/blocky/latest/configuration/](https://0xerr0r.github.io/blocky/latest/configuration/)
- **Add-on Repository**: [https://github.com/robocopklaus/hassio-addon-blocky](https://github.com/robocopklaus/hassio-addon-blocky)

### Getting Help
- **Report Issues**: [GitHub Issues](https://github.com/robocopklaus/hassio-addon-blocky/issues)
- **Upstream Blocky Issues**: [Blocky GitHub](https://github.com/0xERR0R/blocky/issues)
- **Changelog**: See `CHANGELOG.md` for version history and migration guides

### Contributing
Contributions are welcome! Please submit pull requests or issues on GitHub.

### License
This add-on is licensed under the MIT License. Blocky itself is also MIT licensed.

---

**Add-on Version**: 1.0.0
**Blocky Version**: v0.27.0
