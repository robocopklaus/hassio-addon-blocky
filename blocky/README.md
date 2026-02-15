# Blocky Home Assistant Add-on

<figure>
  <img src="https://raw.githubusercontent.com/0xERR0R/blocky/main/docs/blocky.svg" width="200" />
</figure>

![Supports aarch64 Architecture][aarch64-shield]
![Supports amd64 Architecture][amd64-shield]
![Supports armhf Architecture][armhf-shield]
![Supports armv7 Architecture][armv7-shield]

[aarch64-shield]: https://img.shields.io/badge/aarch64-yes-green.svg
[amd64-shield]: https://img.shields.io/badge/amd64-yes-green.svg
[armhf-shield]: https://img.shields.io/badge/armhf-yes-green.svg
[armv7-shield]: https://img.shields.io/badge/armv7-yes-green.svg

A Home Assistant add-on that wraps [Blocky](https://github.com/0xERR0R/blocky) - a fast, lightweight DNS proxy and ad-blocker for your home network with support for DNS-over-TLS, DNS-over-HTTPS, and extensive customization options.

## About

Blocky is a DNS proxy and ad-blocker that sits between your devices and your upstream DNS servers (like Cloudflare or Google DNS). It provides network-wide ad blocking, malware protection, and privacy enhancement without requiring software installation on individual devices.

## Features

- **DNS-based Ad Blocking** - Block ads, trackers, and malicious domains network-wide
- **Multiple Upstream Resolvers** - Configure multiple DNS providers with automatic failover
- **DNS-over-TLS (DoT) & DNS-over-HTTPS (DoH)** - Encrypted DNS queries for enhanced privacy
- **Conditional DNS** - Route specific domains to specific DNS servers
- **Client Groups** - Apply different blocking rules to different devices
- **Custom Block/Allow Lists** - Full control over blocked and allowed domains
- **Query Logging** - Log DNS queries to file, MySQL, PostgreSQL, or CSV
- **Redis Caching** - Optional Redis integration for improved performance
- **EDNS Client Subnet** - Forward client IP subnet information to upstream resolvers
- **Prometheus Metrics** - Built-in metrics endpoint for monitoring
- **Interactive Blocking Status** - Temporarily disable blocking via HTTP API
- **Hostsfile Blocking** - Support for hosts file format blocklists

## Installation

### Via Home Assistant Add-on Store

1. Navigate to **Settings** → **Add-ons** → **Add-on Store** in Home Assistant
2. Click the menu icon (⋮) in the top right and select **Repositories**
3. Add this repository URL: `https://github.com/robocopklaus/hassio-addon-blocky`
4. Find "Blocky" in the add-on list
5. Click **Install**
6. Configure the add-on (see Configuration section below)
7. Click **Start**

### Manual Installation

1. Clone or copy this repository to your Home Assistant add-ons directory:
   ```bash
   cd /addons
   git clone <repository-url> blocky
   ```
2. Restart Home Assistant
3. Navigate to **Settings** → **Add-ons** and install the local add-on

## Configuration

The add-on offers two configuration modes:

### Standard Mode (Recommended)

Configure the add-on through the Home Assistant UI. Your settings are converted to a Blocky configuration automatically. Perfect for most users.

**Key Configuration Options:**

- **Upstream DNS Servers** - Configure your preferred DNS providers (Cloudflare, Google, Quad9, etc.)
- **Blocking Mode** - Choose how blocked domains are handled (zeroIp, nxDomain, etc.)
- **Block Lists** - Select from preset lists or add custom blocklist URLs
- **Allow Lists** - Whitelist specific domains
- **Conditional DNS** - Route specific domains to specific DNS servers
- **Query Logging** - Enable logging to files or databases
- **Client Groups** - Create device-specific blocking rules

### Custom Config Mode

For advanced users who want full control:

1. Enable **Custom Config** in the add-on configuration
2. Place your `config.yml` in `/addon_config/<repository>_blocky/`
3. Your custom configuration will be used directly

**Warning:** In custom config mode, UI settings are ignored and your configuration file will not be overwritten.

## Basic Usage

### Setting Blocky as Your DNS Server

After installation, configure your devices or router to use Blocky:

**Option 1: Router Configuration (Recommended)**
- Set your router's DNS server to your Home Assistant IP address
- All devices on your network will automatically use Blocky

**Option 2: Per-Device Configuration**
- Manually set each device's DNS server to your Home Assistant IP address
- Useful for testing or selective blocking

### HTTP API

Blocky exposes an HTTP API on port 4000 (internal to Home Assistant):

- **Check blocking status:** `http://homeassistant.local:4000/api/blocking/status`
- **Disable blocking:** `http://homeassistant.local:4000/api/blocking/disable?duration=30s`
- **Enable blocking:** `http://homeassistant.local:4000/api/blocking/enable`
- **Query specific domain:** `http://homeassistant.local:4000/api/query?query=example.com`

### Prometheus Metrics

Access Prometheus metrics at: `http://homeassistant.local:4000/metrics`

## Default Block Lists

The add-on includes sensible default blocklists:

1. **StevenBlack Unified Hosts** - Comprehensive ad and malware blocking
2. **Disconnect.me Ads** - Advertising domains
3. **Disconnect.me Tracking** - Analytics and tracking domains

You can disable these or add your own custom lists in the configuration.

## Security Considerations

### Password Storage

**Important:** Home Assistant encrypts passwords in the add-on configuration (using the `password` field type), but they must be written in plaintext to the generated Blocky configuration file (`/addon_config/<repository>_blocky/config.yml`) for Blocky to read them.

**What This Means:**
- Passwords are encrypted in Home Assistant's add-on configuration storage ✓
- Passwords must be in plaintext in Blocky's config files (required by Blocky)
- Configuration files are protected by container isolation and file system permissions
- Files are only accessible within the add-on container and mounted volumes

**Best Practices:**
- Use strong, unique passwords for Redis and database connections
- Ensure your Home Assistant installation follows security best practices
- Avoid sharing configuration files or backups containing credentials
- Restrict access to your Home Assistant instance

### Network Exposure

- **DNS Port (53):** Required for DNS resolution, exposed to your local network
- **HTTP API Port (4000):** Metrics and control interface, consider access restrictions
- Blocky does not require internet-facing exposure

### Query Logging Privacy

Query logs contain all DNS requests from your network, which may include sensitive information:
- Websites visited by household members
- Smart device communication patterns
- Application network activity

Recommendations:
- Only enable query logging if necessary
- Restrict access to log files
- Consider privacy implications before enabling database logging
- Regularly rotate or purge old logs

## Troubleshooting

### Add-on Won't Start

1. Check the add-on logs in Home Assistant
2. Verify port 53 is not in use by another service
3. Ensure upstream DNS servers are reachable
4. Validate your configuration (check for YAML syntax errors in custom config mode)

### DNS Resolution Not Working

1. Verify Blocky is running: Check add-on status
2. Test DNS resolution: `nslookup example.com <HA_IP>`
3. Check upstream DNS configuration
4. Review logs for connection errors to upstream servers

### Websites Blocked Incorrectly

1. Check logs to see which blocklist is blocking the domain
2. Add domain to allowlist in configuration
3. Review and adjust your blocklists
4. Temporarily disable blocking to verify: `http://<HA_IP>:4000/api/blocking/disable`

### High Memory Usage

1. Reduce number of blocklists
2. Disable query logging
3. Reduce cache size settings
4. Check for excessive query rates

### Can't Access Add-on Configuration

1. Ensure Home Assistant is up to date
2. Restart the add-on
3. Check Home Assistant system logs
4. Try disabling custom config mode

## Support & Links

- **Blocky Documentation:** https://0xerr0r.github.io/blocky/
- **Blocky GitHub:** https://github.com/0xERR0R/blocky
- **Home Assistant Add-ons:** https://www.home-assistant.io/addons/
- **Report Issues:** Open an issue in this repository
- **Discussions:** Use GitHub Discussions for questions and community support

## Advanced Topics

For advanced configuration, troubleshooting, and integration examples, see [DOCS.md](DOCS.md).

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history and changes.

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Credits

- **Blocky** by [0xERR0R](https://github.com/0xERR0R)
- **Add-on** maintained by Robocop Klaus
- Built on [Home Assistant Add-on Base Images](https://github.com/home-assistant/docker-base)

## Architecture Support

This add-on supports the following architectures:

- `amd64` - Intel/AMD 64-bit (x86_64)
- `armv7` - ARM 32-bit (ARMv7)
- `aarch64` - ARM 64-bit (ARMv8)
- `armhf` - ARM 32-bit (older ARM devices)