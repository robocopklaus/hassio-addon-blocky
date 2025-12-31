# https://developers.home-assistant.io/docs/add-ons/configuration#add-on-dockerfile
# renovate: datasource=docker depName=ghcr.io/home-assistant/amd64-base
ARG HOME_ASSISTANT_BASE_VERSION=3.23
ARG BUILD_ARCH=amd64
ARG BUILD_FROM="ghcr.io/home-assistant/${BUILD_ARCH}-base:${HOME_ASSISTANT_BASE_VERSION}"
FROM ${BUILD_FROM}

# Set shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Setup base
ARG BUILD_ARCH
# renovate: datasource=github-releases depName=0xERR0R/blocky
ARG BLOCKY_VERSION=v0.27.0
# renovate: datasource=github-releases depName=home-assistant/tempio
ARG TEMPIO_VERSION=2024.11.2

# Install Tempio for config templating
# Note: Tempio is from official Home Assistant org and doesn't publish checksums
RUN \
    curl -sSLf -o /usr/bin/tempio \
    "https://github.com/home-assistant/tempio/releases/download/${TEMPIO_VERSION}/tempio_${BUILD_ARCH}" \
    && chmod +x /usr/bin/tempio

# Install dependencies
RUN apk add --no-cache \
    ca-certificates \
    curl \
    tzdata

# Download Blocky binary based on architecture
RUN \
    case "${BUILD_ARCH}" in \
        amd64) ARCH="x86_64" ;; \
        armv7) ARCH="armv7" ;; \
        aarch64) ARCH="arm64" ;; \
        armhf) ARCH="armv6" ;; \
        *) echo "Unsupported architecture: ${BUILD_ARCH}" && exit 1 ;; \
    esac \
    && BLOCKY_TARBALL="blocky_${BLOCKY_VERSION}_Linux_${ARCH}.tar.gz" \
    && echo "Downloading Blocky ${BLOCKY_VERSION} for ${ARCH}..." \
    && curl -sSLf -o "/tmp/${BLOCKY_TARBALL}" \
        "https://github.com/0xERR0R/blocky/releases/download/${BLOCKY_VERSION}/${BLOCKY_TARBALL}" \
    && echo "Downloading checksums..." \
    && curl -sSLf -o /tmp/blocky_checksums.txt \
        "https://github.com/0xERR0R/blocky/releases/download/${BLOCKY_VERSION}/blocky_checksums.txt" \
    && echo "Verifying checksum..." \
    && cd /tmp \
    && grep "${BLOCKY_TARBALL}" blocky_checksums.txt | sha256sum -c - \
    && echo "Checksum verified successfully" \
    && tar -xzf "${BLOCKY_TARBALL}" -C /tmp \
    && mv /tmp/blocky /usr/local/bin/blocky \
    && chmod +x /usr/local/bin/blocky \
    && rm -rf /tmp/*

# Verify installation
RUN blocky version

# Copy root filesystem
COPY rootfs /

# Build arguments
ARG BUILD_DATE
ARG BUILD_DESCRIPTION
ARG BUILD_NAME
ARG BUILD_REF
ARG BUILD_REPOSITORY
ARG BUILD_VERSION

# Labels
LABEL \
    io.hass.name="${BUILD_NAME}" \
    io.hass.description="${BUILD_DESCRIPTION}" \
    io.hass.arch="${BUILD_ARCH}" \
    io.hass.type="addon" \
    io.hass.version="${BUILD_VERSION}" \
    maintainer="Fabian Pahl <hi@robocopklaus.dev>" \
    org.opencontainers.image.title="${BUILD_NAME}" \
    org.opencontainers.image.description="${BUILD_DESCRIPTION}" \
    org.opencontainers.image.vendor="Home Assistant Community Add-ons" \
    org.opencontainers.image.authors="Fabian Pahl <hi@robocopklaus.dev>" \
    org.opencontainers.image.licenses="MIT" \
    org.opencontainers.image.url="https://github.com/${BUILD_REPOSITORY}" \
    org.opencontainers.image.source="https://github.com/${BUILD_REPOSITORY}" \
    org.opencontainers.image.documentation="https://github.com/${BUILD_REPOSITORY}/blob/main/README.md" \
    org.opencontainers.image.created="${BUILD_DATE}" \
    org.opencontainers.image.revision="${BUILD_REF}" \
    org.opencontainers.image.version="${BUILD_VERSION}"

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD blocky blocking status || exit 1
