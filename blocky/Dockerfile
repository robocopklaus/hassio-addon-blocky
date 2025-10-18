# https://developers.home-assistant.io/docs/add-ons/configuration#add-on-dockerfile
ARG BUILD_FROM
FROM $BUILD_FROM

# Execute during the build of the image
ARG TEMPIO_VERSION BUILD_ARCH
RUN \
  curl -sSLf -o /usr/bin/tempio \
  "https://github.com/home-assistant/tempio/releases/download/${TEMPIO_VERSION}/tempio_${BUILD_ARCH}"

# Setup blocky
# renovate: datasource=repology depName=alpine_edge/blocky versioning=loose
RUN apk add --no-cache --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community blocky=0.25-r1

# Copy root filesystem
COPY rootfs /
