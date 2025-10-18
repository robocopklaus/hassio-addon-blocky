# Blocky Home Assistant Add-On Documentation

## Overview

Blocky is a DNS proxy and ad-blocker designed for the Home Assistant platform. It enhances network performance and security by blocking unwanted content and providing advanced DNS configuration options.

## Table of Contents

1. [Installation](#installation)
2. [Configuration](#configuration)
3. [Features](#features)
4. [Prometheus & Grafana Integration](#prometheus--grafana-integration)
5. [Usage](#usage)
6. [Troubleshooting](#troubleshooting)
7. [FAQs](#faqs)
8. [Contributing](#contributing)
9. [License](#license)

## Installation

Detailed steps on how to install the Blocky add-on in Home Assistant.

### Prerequisites

- Home Assistant installed
- Basic knowledge of Home Assistant add-ons

### Installation Steps

1. Navigate to...
2. Click on...

## Configuration

Guidelines on how to configure Blocky once installed.

### Accessing Configuration

- How to access the configuration panel

### Configuration Options

- Explanation of each configuration option

## Features

A detailed overview of Blocky's features.

- DNS Query Blocking
- Advanced DNS Settings
- Protocol Support

## Prometheus & Grafana Integration

Blocky includes built-in support for exporting metrics to Prometheus, enabling powerful visualization and monitoring capabilities through Grafana dashboards.

### Enabling Prometheus Metrics

To enable Prometheus metrics collection, add the following to your add-on configuration:

```yaml
prometheus:
  enabled: true
  port: 4000
  path: /metrics
```

**Configuration Options:**

- `enabled` (boolean, default: `false`): Enable or disable Prometheus metrics endpoint
- `port` (integer, default: `4000`): Port for the HTTP metrics endpoint
- `path` (string, default: `/metrics`): URL path for the metrics endpoint

After enabling, the metrics endpoint will be available at `http://<your-home-assistant-ip>:4000/metrics`

### Setting Up Prometheus in Home Assistant

If you have Prometheus running in Home Assistant (via add-on or integration), add this scrape configuration:

```yaml
scrape_configs:
  - job_name: 'blocky'
    static_configs:
      - targets: ['<addon-hostname>:4000']
```

For Home Assistant add-ons, you can typically use the add-on's hostname or the local IP address.

### Grafana Dashboard

Blocky provides a comprehensive Grafana dashboard for visualizing DNS metrics.

**To import the dashboard:**

1. Open your Grafana instance
2. Navigate to **Dashboards** → **Import**
3. Enter dashboard ID: **13768**
4. Click **Load**
5. Select your Prometheus data source
6. Click **Import**

Alternatively, you can download the dashboard JSON directly from [Grafana.com](https://grafana.com/grafana/dashboards/13768)

### Available Metrics

The Prometheus endpoint exposes the following key metrics:

**Query Metrics:**
- `blocky_query_total` - Total number of DNS queries
- `blocky_response_total` - Total number of responses by type (blocked, cached, resolved)
- `blocky_request_duration_ms_bucket` - Query latency histograms

**Blocking Metrics:**
- `blocky_blocking_enabled` - Current blocking status (0=disabled, 1=enabled)
- `blocky_blacklist_cache` - Number of entries in blacklist cache by group

**Cache Metrics:**
- `blocky_cache_hit_total` - Number of cache hits
- `blocky_cache_miss_total` - Number of cache misses
- `blocky_prefetch_count` - Number of prefetched domains

**Resolver Metrics:**
- `blocky_upstream_resolver_status` - Status of upstream DNS resolvers

### Dashboard Features

The Grafana dashboard (ID 13768) includes:

- **Total queries by domain and client** - See which domains are being queried most frequently
- **Allowed vs blocked queries** - Visualize blocking effectiveness
- **Query latency** - Monitor DNS resolution performance
- **Resolver performance** - Track upstream DNS server health and response times
- **Cache statistics** - Analyze cache hit rates and efficiency
- **Blocking toggle** - Enable/disable blocking directly from Grafana (via API)

### Benefits

- **Real-time visibility** into DNS traffic patterns
- **Performance monitoring** with detailed latency metrics
- **Security insights** through blocked query analysis
- **Network troubleshooting** by identifying DNS issues
- **Historical trends** for capacity planning

For more information, visit the [official Blocky Prometheus documentation](https://0xerr0r.github.io/blocky/latest/prometheus_grafana/).

## Usage

Examples and best practices for using Blocky in a Home Assistant environment.

### Example Scenarios

- Blocking ads and malicious domains
- Custom DNS resolutions

## Troubleshooting

Common issues and solutions.

- Issue: Blocky not blocking ads
- Solution: Check blacklist configuration

## FAQs

Answers to frequently asked questions about Blocky.

1. **Q**: How do I update the blacklist?
   **A**: ...

2. **Q**: Can Blocky work with other DNS services?
   **A**: ...

## Contributing

Information for those who wish to contribute to the Blocky project.

- Guidelines for submitting issues
- Process for submitting pull requests

## License

Details of the licensing of Blocky.

- Link to the full license text

---

For more information, visit [Blocky on GitHub](https://github.com/robocopklaus/hassio-addon-blocky).
