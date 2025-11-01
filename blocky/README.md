# Home Assistant Add-on: Blocky

<figure>
  <img src="https://raw.githubusercontent.com/0xERR0R/blocky/main/docs/blocky.svg" width="200" />
</figure>

Fast and lightweight DNS proxy and ad-blocker for your Home Assistant network.

## About

Blocky is a DNS proxy, DNS enhancer, and ad-blocker for your local network with many features. This add-on packages Blocky as a Home Assistant add-on, providing an easy way to add network-wide ad-blocking and DNS privacy to your Home Assistant installation.

## Features

- **DNS-based Ad Blocking**: Block ads, trackers, and malware at the DNS level
- **Multiple Block Lists**: Support for various block list sources and formats
- **Privacy-Focused DNS**: Support for DNS-over-TLS (DoT) and DNS-over-HTTPS (DoH) upstream resolvers
- **Fast Performance**: Efficient caching and query processing
- **Conditional DNS**: Route specific domains to designated DNS servers (useful for local network domains)
- **Client-Specific Rules**: Apply different blocking rules per client or group
- **REST API**: Query status, metrics, and control via HTTP API
- **Flexible Configuration**: UI-driven configuration or custom YAML for advanced features

## Installation

1. Navigate to **Settings** → **Add-ons** → **Add-on Store** in your Home Assistant interface
2. Add this repository URL (if not already added): `https://github.com/robocopklaus/hassio-addon-blocky`
3. Find "Blocky" in the add-on store and click on it
4. Click **Install**
5. Configure the add-on (see Configuration section below)
6. Click **Start**
7. Configure your devices or router to use your Home Assistant IP as their DNS server

## Configuration

### Standard Mode (Recommended)

The add-on provides a user-friendly configuration interface for common options:

#### Upstream DNS Servers
Configure which DNS servers Blocky should use for resolving queries. Supports:
- Plain DNS: `1.1.1.1`
- DNS-over-TLS: `tcp-tls:one.one.one.one`
- DNS-over-HTTPS: `https://cloudflare-dns.com/dns-query`

**Default**: Cloudflare and Google DNS with DoT/DoH

#### Bootstrap DNS Servers
Plain IP addresses used to resolve DoH/DoT upstream hostnames. Should be reliable public DNS servers.

**Default**: `1.1.1.1`, `8.8.8.8`

#### Block Lists
Configure groups of block lists (e.g., ads, tracking, malware) and assign them to clients. The add-on comes with sensible defaults:
- **ads**: Steven Black's hosts, Disconnect.me ad lists
- **tracking**: Disconnect.me tracking lists

#### Conditional DNS Mapping
Route specific domains to designated DNS servers. Useful for:
- Local network domains (e.g., `fritz.box` → `192.168.178.1`)
- Corporate VPN domains
- Custom local DNS servers

Each mapping accepts a domain plus one or more resolvers. Provide multiple upstreams by
listing them as separate entries in the UI; the add-on will emit the comma-separated
format Blocky expects—for example:

```yaml
conditional:
  mapping:
    fritz.box: 192.168.178.1,192.168.178.2
```

#### Caching
Configure DNS response caching for improved performance:
- **Minimum Cache Time**: Override short TTLs (default: 5m)
- **Maximum Cache Time**: Cap long TTLs (default: 30m)
- **Prefetching**: Automatically refresh popular domains (recommended)

**Note**: The HTTP API port is fixed at 4000 (container-side). Users can change the host-side port mapping via the Network tab if needed.

### Custom Configuration Mode

For advanced users who need features not exposed in the UI:

1. Enable **Custom Configuration** in the add-on settings
2. The current configuration will be saved to `/addon_config/<repository>_blocky/config.yml`
3. Edit this file directly to access all Blocky features
4. Restart the add-on to apply changes

**Warning**: When custom configuration is enabled, all UI options are ignored. Toggle it OFF to return to UI-driven configuration.

#### Custom Configuration Features
- Advanced upstream DNS configurations
- Custom Redis integration
- Query logging settings
- Custom DNS records
- EDNS client subnet
- Safe search enforcement
- And much more - see [Blocky documentation](https://0xerr0r.github.io/blocky/latest/configuration/)

## Usage

### Setting Up Network-Wide DNS

#### Option 1: Router Configuration (Recommended)
Configure your router's DHCP server to provide your Home Assistant IP as the primary DNS server. This applies to all devices on your network.

#### Option 2: Per-Device Configuration
Manually configure each device to use your Home Assistant IP as its DNS server.

### Checking Status

- **Health Check**: `curl http://homeassistant.local:4000/api/health`
- **Metrics**: `curl http://homeassistant.local:4000/metrics` (Prometheus format)
- **Query Status**: Check the add-on logs for query information

### REST API

Blocky provides a REST API for control and status:

- `GET /api/blocking/status` - Check if blocking is enabled
- `POST /api/blocking/enable` - Enable blocking
- `POST /api/blocking/disable` - Disable blocking
- `GET /api/query` - Query DNS records
- And more - see [Blocky API documentation](https://0xerr0r.github.io/blocky/latest/api/)

## Troubleshooting

### DNS Not Working

1. Verify the add-on is running: Check the add-on status
2. Check logs: Review add-on logs for errors
3. Test DNS resolution: `nslookup google.com <homeassistant-ip>`
4. Verify configuration: Ensure your upstream DNS servers are correct

### Ads Not Blocked

1. Confirm block lists are configured and assigned to your client/group
2. Check if your device is bypassing DNS (some apps use hardcoded DNS)
3. Clear device DNS cache
4. Review logs to see if queries are being blocked

### Custom Configuration Not Applied

1. Verify **Custom Configuration** is enabled
2. Check YAML syntax: The add-on validates YAML on startup
3. Review add-on logs for configuration errors
4. Consult [Blocky documentation](https://0xerr0r.github.io/blocky/latest/configuration/) for correct syntax

### Performance Issues

1. Adjust cache settings (increase max cache time)
2. Enable prefetching
3. Reduce number of block lists
4. Check upstream DNS server response times

## Security

This add-on implements the following measures today:

- **Binary Verification**: Blocky binaries are verified with SHA256 checksums from official releases
- **HTTPS Block Lists**: Default block lists are fetched over encrypted connections
- **Bootstrap DNS Validation**: UI restricts bootstrap entries to IP literals to avoid hijacking

> **Note**: AppArmor confinement and capability drops are temporarily disabled due to upstream
> compatibility issues. They will return once the profile is stable across host releases.

## Support

- **Documentation**: [Blocky Official Docs](https://0xerr0r.github.io/blocky/)
- **Issues**: [GitHub Issues](https://github.com/robocopklaus/hassio-addon-blocky/issues)
- **Blocky Project**: [github.com/0xERR0R/blocky](https://github.com/0xERR0R/blocky)

## Authors & License

- **Add-on Author**: Fabian Pahl ([@robocopklaus](https://github.com/robocopklaus))
- **Blocky Author**: [0xERR0R](https://github.com/0xERR0R)
- **License**: MIT

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history and changes.
