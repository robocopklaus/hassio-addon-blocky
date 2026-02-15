<div align="center">
  <img height="200" src="https://raw.githubusercontent.com/0xERR0R/blocky/main/docs/blocky.svg">
  <h1>Blocky Home Assistant Add-On</h1>
  <p>A powerful DNS proxy and ad-blocker for your Home Assistant ecosystem.</p>

  [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
  ![Supports amd64 Architecture](https://img.shields.io/badge/amd64-yes-green.svg)
  ![Supports aarch64 Architecture](https://img.shields.io/badge/aarch64-yes-green.svg)
  ![Supports armv7 Architecture](https://img.shields.io/badge/armv7-yes-green.svg)
  ![Supports armhf Architecture](https://img.shields.io/badge/armhf-yes-green.svg)
</div>

## About

This repository contains a Home Assistant add-on that packages [Blocky](https://github.com/0xERR0R/blocky) (v0.28.2), a fast and lightweight DNS proxy and ad-blocker. Blocky provides network-wide ad blocking, privacy protection, and advanced DNS features for your entire network through a single Home Assistant add-on.

### Key Features

- **Network-Wide Ad Blocking** - Block ads, trackers, and malicious domains across all devices
- **Modern DNS Protocols** - Support for DNS-over-TLS (DoT) and DNS-over-HTTPS (DoH)
- **Multiple Upstream Resolvers** - Configure multiple DNS providers with intelligent query distribution
- **Split-DNS / Conditional Routing** - Route specific domains to designated DNS servers
- **Custom DNS Mappings** - Define local hostname-to-IP mappings without upstream forwarding
- **Client Groups & Identification** - Apply different blocking rules per device or client
- **Query Logging** - Record DNS queries to CSV, MySQL, PostgreSQL, or console
- **Redis Integration** - Synchronize cache across multiple Blocky instances
- **Prometheus Metrics** - Built-in monitoring endpoint for observability
- **HTTP API** - Programmatically control blocking, test queries, and refresh blocklists
- **Smart Caching** - DNS response caching with prefetching support

## Quick Start

This add-on can be installed directly from the Home Assistant Add-on Store or by adding this repository manually.

**For complete installation and usage instructions**, see the [Add-on README](./blocky/README.md).

### Requirements

- Home Assistant OS or Home Assistant Supervised
- Supported architecture: amd64, aarch64, armv7, or armhf

### Basic Setup

1. Install the add-on
2. Configure your upstream DNS servers and blocklists
3. Start the add-on
4. Point your router or devices to use your Home Assistant IP as the DNS server

## Documentation

This repository contains documentation for different audiences:

| Document | Audience | Contents |
|----------|----------|----------|
| [blocky/README.md](./blocky/README.md) | **Users** | Installation, configuration, usage, troubleshooting |
| [blocky/DOCS.md](./blocky/DOCS.md) | **Advanced Users** | Complete configuration reference, API documentation, performance tuning |
| [blocky/CLAUDE.md](./blocky/CLAUDE.md) | **Developers** | Architecture, development workflow, contribution guidelines |

## Repository Structure

```
.
├── blocky/                   # Main add-on directory
│   ├── config.yaml           # Add-on configuration schema
│   ├── DOCS.md               # Technical configuration reference
│   ├── README.md             # User-facing documentation
│   ├── CLAUDE.md             # Developer documentation
│   ├── Dockerfile            # Multi-architecture container build
│   ├── rootfs/               # Container filesystem overlay
│   │   ├── etc/cont-init.d/  # Initialization scripts
│   │   ├── etc/services.d/   # Service management scripts
│   │   └── usr/share/tempio/ # Configuration templates
│   └── translations/         # UI field descriptions
├── .github/workflows/        # CI/CD automation
├── scripts/                  # Build and release utilities
└── README.md                 # This file
```

## Configuration

The add-on supports two configuration modes:

1. **Standard Mode** (Recommended) - Configure through the Home Assistant UI with guided options
2. **Custom Config Mode** - Use a custom Blocky YAML configuration file for advanced features

See the [documentation](./blocky/README.md#configuration) for details.

## Contributing

Contributions are welcome! Here's how you can help:

### Reporting Issues

If you encounter problems or have feature requests, please [open an issue](https://github.com/yourusername/hassio-addon-blocky/issues) with:
- A clear description of the issue
- Steps to reproduce (if applicable)
- Your Home Assistant version and architecture
- Relevant logs from the add-on

### Development

For development setup and guidelines, see [CLAUDE.md](./blocky/CLAUDE.md).

This project uses:
- **Conventional Commits** for commit messages
- **Semantic Release** for automated versioning and releases
- **Multi-architecture Docker builds** for broad platform support

### Testing

Before submitting a PR:
1. Test your changes on your Home Assistant instance
2. Verify the add-on starts successfully
3. Check that DNS resolution works as expected
4. Ensure any configuration changes are properly documented

## Credits

- **Upstream Project**: [Blocky](https://github.com/0xERR0R/blocky) by [@0xERR0R](https://github.com/0xERR0R)
- **Home Assistant Community**: For the excellent add-on ecosystem and tools
- **Contributors**: Everyone who has helped improve this add-on

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

The upstream Blocky project is licensed under the Apache License 2.0.

## Support

- **Add-on Issues**: [GitHub Issues](https://github.com/yourusername/hassio-addon-blocky/issues)
- **Blocky Documentation**: [Official Blocky Docs](https://0xerr0r.github.io/blocky/)
- **Home Assistant Community**: [Community Forum](https://community.home-assistant.io/)

---

<div align="center">
  Made with ❤️ for the Home Assistant community
</div>
