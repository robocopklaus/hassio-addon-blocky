<div align="center">
  <img height="200" src="https://raw.githubusercontent.com/0xERR0R/blocky/main/docs/blocky.svg">
  <h1>Blocky Home Assistant Add-On</h1>
  <p>A powerful DNS proxy and ad-blocker for your Home Assistant ecosystem.</p>
</div>

## About

This repository provides a Home Assistant add-on that integrates [Blocky](https://github.com/0xERR0R/blocky) into your Home Assistant ecosystem, enabling network-wide ad blocking and advanced DNS features.

Blocky is an advanced DNS proxy and ad-blocking solution offering features like custom DNS resolution, conditional forwarding, performance enhancement through caching and prefetching, and support for modern DNS protocols including DNS over HTTPS (DoH) and DNS over TLS (DoT). It's designed with a privacy-centric approach, collecting no user data while providing security-focused features like DNSSEC and enhanced DNS (eDNS) support.

## Installation

### Quick Installation (Recommended)

[![Add Repository to Home Assistant](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Frobocopklaus%2Fhassio-addon-blocky)

### Manual Installation

1. Navigate to **[Settings → Add-ons → Add-on Store](https://my.home-assistant.io/redirect/supervisor_store/)** in your Home Assistant instance
2. Click on the three dots menu (⋮) in the top right and select **Repositories**
3. Add this repository URL:
   ```
   https://github.com/robocopklaus/hassio-addon-blocky
   ```
4. Click **Add** → **Close**
5. Find "Blocky DNS Proxy" in the add-on list
6. Click **Install** and wait for the installation to complete
7. Click **Start**

## Configuration

After installation, configure Blocky to suit your network needs:

1. Navigate to the Blocky add-on in Home Assistant
2. Go to the **Configuration** tab
3. Modify the settings according to your preferences (see [add-on documentation](blocky/README.md) for detailed options)
4. Save your changes
5. Restart the add-on for the configuration to take effect

For detailed configuration options and examples, refer to the [add-on documentation](blocky/README.md) and the [official Blocky configuration guide](https://0xerr0r.github.io/blocky/latest/).

## Add-ons in this Repository

### Blocky DNS Proxy

Fast and lightweight DNS proxy and ad-blocker for your network.

**Features:**
- **Ad Blocking** - Customizable blocklists for ads, trackers, and malware
- **Fast DNS Resolution** - Built-in caching and prefetching for improved performance
- **Modern DNS Protocols** - Support for DNS over HTTPS (DoH) and DNS over TLS (DoT)
- **Security** - DNSSEC validation and enhanced DNS (eDNS) support
- **Conditional Forwarding** - Advanced DNS settings per client group
- **Custom DNS Overrides** - Define custom DNS resolution for specific domains
- **Privacy-Focused** - No user data collection or tracking
- **Monitoring** - Prometheus metrics and HTTP API for insights
- **Low Resource Usage** - Efficient and lightweight design

For detailed documentation, configuration options, and usage examples, see the [add-on documentation](blocky/README.md).

## Usage Examples

Blocky can be used to:

- **Enhance Network Security** - Block malicious domains, phishing sites, and malware distribution networks
- **Improve Browsing Speed** - Reduce ad load times and improve page performance with DNS caching
- **Customize DNS Resolution** - Set up custom DNS entries for local services and domains in your network
- **Protect Privacy** - Block tracking domains while using secure DNS protocols (DoH/DoT)
- **Parental Controls** - Configure blocklists to restrict access to inappropriate content

## Support

- **Blocky Documentation**: https://0xerr0r.github.io/blocky/latest/
- **Blocky GitHub**: https://github.com/0xERR0R/blocky
- **Report Issues**: https://github.com/robocopklaus/hassio-addon-blocky/issues

## Development

Want to test the add-on locally or contribute to development? See [DEVELOPMENT.md](DEVELOPMENT.md) for:

- Setting up a local Home Assistant test environment
- Building and testing the add-on locally
- Debugging common issues
- Testing the AppArmor profile
- Using helper scripts for quick iteration

**Quick Start:**
```bash
# Build and test locally (requires Docker)
./scripts/build-docker.sh amd64
```

For full integration testing with Home Assistant, see the [complete development guide](DEVELOPMENT.md).

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. See [CONTRIBUTING.md](blocky/CONTRIBUTING.md) for guidelines.

## License

This Home Assistant add-on repository is licensed under the MIT License. See [LICENSE](LICENSE) for details.

Blocky itself is licensed under Apache License 2.0.

## Credits

- **Blocky** by [0xERR0R](https://github.com/0xERR0R)
- **Home Assistant Add-on** by [Fabian Pahl](https://github.com/robocopklaus)
