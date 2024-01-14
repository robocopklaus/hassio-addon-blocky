<div align="center">
  <img height="200" src="https://github.com/0xERR0R/blocky/blob/main/docs/blocky.svg">
  <h1>Blocky Home Assistant Add-On</h1>
  <p>A powerful DNS proxy and ad-blocker for your Home Assistant ecosystem.</p>
</div>

## Introduction

Blocky is an advanced DNS proxy and ad-blocking add-on designed for Home Assistant, offering features like custom DNS resolution, conditional forwarding, performance enhancement through caching, and support for modern DNS protocols including DoH and DoT.

## Features

- DNS query blocking with customizable lists (e.g., ads, malware)
- Advanced DNS settings per client group
- Performance enhancements via caching and prefetching
- Supports DNS over HTTPS/TLS
- Security-focused with DNSSEC and eDNS
- Privacy-centric design without user data collection
- Easy to set up and configure

## Installation

1. Navigate to **[Settings → Add-ons → Add-on Store](https://my.home-assistant.io/redirect/supervisor_store/)** in Home Assistant.
2. Click **⋮ → Repositories**, enter `https://github.com/robocopklaus/hassio-addon-blocky` and click **Add → Close**. Alternatively, use the [Add-on Repository Badge](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Frobocopklaus%2Fhassio-addon-blocky) for a quick setup.
3. Find the Blocky add-on in the store, click on it, and press **Install**. Wait for the installation to complete.

## Post-Installation Configuration

After installation, configure Blocky via the Home Assistant interface:

- Access the Blocky add-on and navigate to the 'Configuration' tab.
- Modify the settings as needed to suit your network and preferences.
- Save your changes and restart the add-on for them to take effect.

For detailed configuration options and examples, refer to the Blocky Configuration Guide.

## Usage

Blocky can be used to:

- Enhance network security by blocking malicious domains.
- Improve browsing speed by reducing ad load times.
- Customize DNS resolution for specific domains in your network.
