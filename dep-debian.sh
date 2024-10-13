#!/bin/bash

set -xeuo pipefail # Make my life easier

# Install Dependency for Debian 12

./dep-common.sh

# Add source
cat > /etc/apt/sources.list.d/immich << EOL
deb http://deb.debian.org/debian testing main contrib
EOL

# Add package priority to preference
cat > /etc/apt/preferences.d/immich << EOL
Package: *
Pin: release a=testing
Pin-Priority: 450
EOL

# libjpeg62-turbo-dev
apt install --no-install-recommends -y \
        libjpeg62-turbo-dev
## libjpeg-turbo is faster than libjpeg

# Dockerfile 35
apt install -t testing --no-install-recommends -y \
        libdav1d-dev \
        libhwy-dev \
        libwebp-dev \
        libio-compress-brotli-perl

## Dockerfile 92
apt install -t testing --no-install-recommends -y \
        libio-compress-brotli-perl \
        libwebp7 \
        libwebpdemux2 \
        libwebpmux3 \
        libhwy1t64

## Dockerfile 104
apt install -t testing --no-install-recommends -y \
        intel-media-va-driver-non-free