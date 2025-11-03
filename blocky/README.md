# Home Assistant Add-on: Blocky

<figure>
  <img src="https://raw.githubusercontent.com/0xERR0R/blocky/main/docs/blocky.svg" width="200" />
</figure>

Fast and lightweight DNS proxy and ad-blocker for your Home Assistant network.

## About

Blocky is a DNS proxy and ad-blocker that operates at the network level, providing comprehensive protection for all devices on your network without requiring software installation on each device. Unlike browser-based ad-blockers, Blocky blocks ads, trackers, and malicious domains at the DNS level before connections are even established.

**Key Highlights:**
- **Network-wide protection**: Blocks ads and trackers for all connected devices (phones, tablets, smart TVs, IoT devices)
- **No web UI**: Operates as a DNS service (configuration via Home Assistant UI, metrics available at port 4000)
- **Privacy-first**: Zero telemetry, no data collection, completely private
- **High performance**: Efficient caching, prefetching, and low memory footprint suitable for Raspberry Pi
- **Modern DNS protocols**: Support for DNS-over-HTTPS (DoH) and DNS-over-TLS (DoT)

## Features

### DNS Blocking & Filtering
- External block lists for ads, trackers, and malware
- Built-in denylist and allowlist management from the Home Assistant UI
- Assign blocking groups to clients (default group included)
- Support for custom block lists
- Advanced blocking via custom configuration (regex, per-client rules)

### DNS Resolution
- Multiple upstream DNS resolvers with automatic failover
- DNS-over-HTTPS (DoH) and DNS-over-TLS (DoT) support
- Plain DNS for maximum performance
- Bootstrap DNS for resolving DoH/DoT upstream hostnames

### Local Network Integration
- Conditional DNS mapping for local hostnames (router, NAS, printers)
- Client name resolution via reverse DNS lookup
- Unqualified hostname resolution (single-word names)

### Performance Optimization
- Configurable DNS response caching
- Automatic prefetching for frequently accessed domains
- Low memory footprint (~20 MB RAM)
- Stateless operation, no database required

### Monitoring & Observability
- Prometheus metrics endpoint (port 4000)
- Query statistics and blocked domain counts
- Health check endpoint
- Query logging (via custom configuration)

### Flexible Configuration
- User-friendly UI options for common settings
- Custom configuration mode for advanced users
- Access to all Blocky features via direct config file editing
- Per-client blocking rules (custom config mode)

## Quick Start

### Installation

1. **Add Repository**: Settings → Add-ons → Add-on Store → ⋮ → Repositories
   ```
   https://github.com/robocopklaus/hassio-addon-blocky
   ```

2. **Install**: Find "Blocky" in the add-on store and click Install

3. **Configure**:
   - Go to Configuration tab
   - Review and adjust upstream DNS servers
   - Configure the default denylist and add allowlist exceptions if needed
   - Save and start the add-on

4. **Network Setup**: Configure your router's DHCP to use Home Assistant's IP as DNS server, or configure devices individually

### Minimum Configuration

The add-on works out-of-the-box with sensible defaults:
- Upstream DNS: Cloudflare and Google (DoT/DoH)
- Block lists: Ads (StevenBlack hosts)
- Caching: 5-30 minutes with prefetching enabled

Simply start the add-on and point your devices to use Home Assistant's IP as their DNS server.

## Documentation

- **[Full Documentation](DOCS.md)**: Complete configuration guide, use cases, and troubleshooting
- **[Changelog](CHANGELOG.md)**: Version history and migration guides
- **[Blocky Official Docs](https://0xerr0r.github.io/blocky/)**: Upstream Blocky documentation for advanced features

## Configuration Highlights

### Upstream DNS Servers
Choose from multiple protocols:
- **DoH**: `https://cloudflare-dns.com/dns-query`
- **DoT**: `tcp-tls:one.one.one.one`
- **Plain DNS**: `1.1.1.1` (fastest, unencrypted)

### Blocking & Allowlisting
- Enable or disable the default `ads` denylist sourced from StevenBlack hosts
- Create additional denylists pointing to remote URLs or local files
- Define allowlists for exceptions and assign denylists to client groups (default group included)

### Local Network Resolution
Map local domains to local DNS servers:
```yaml
conditional_mapping:
  - domain: "fritz.box"
    resolvers:
      - "192.168.178.1"
```

### Custom Configuration Mode
Enable `custom_config` to access all Blocky features:
- Per-client blocking rules
- Query logging
- Advanced allowlists (regex, per-client exceptions)
- Regex-based blocking
- And much more...

See [DOCS.md](DOCS.md) for detailed configuration examples.

## Monitoring

Access Blocky metrics and health status:
- **Metrics**: `http://<home-assistant-ip>:4000/metrics` (Prometheus format)
- **Health**: `http://<home-assistant-ip>:4000/` (JSON status)

Compatible with Grafana for visualization.

## Support

- **Issues**: [GitHub Issues](https://github.com/robocopklaus/hassio-addon-blocky/issues)
- **Blocky Upstream**: [0xERR0R/blocky](https://github.com/0xERR0R/blocky)
- **Home Assistant Community**: [Home Assistant Forums](https://community.home-assistant.io/)

## Technical Details

- **Blocky Version**: v0.27.0
- **Supported Architectures**: amd64, armv7, aarch64, armhf
- **Base OS**: Alpine Linux 3.20
- **Ports**: 53 (DNS TCP/UDP), 4000 (HTTP API/metrics)
- **Memory**: ~20 MB RAM typical usage
- **License**: MIT

