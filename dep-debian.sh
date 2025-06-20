#!/bin/bash

set -xeuo pipefail # Make my life easier

# Install Dependency for Debian 12

# Add source
if [ ! -d "/etc/apt/sources.list.d/immich.list" ]; then
    cat > /etc/apt/sources.list.d/immich.list << EOL
deb http://deb.debian.org/debian testing main contrib
EOL
fi

# Add package priority to preference
if [ ! -d "/etc/apt/preferences.d/immich" ]; then
    cat > /etc/apt/preferences.d/immich << EOL
Package: *
Pin: release a=testing
Pin-Priority: -10
EOL
fi

# Update before install from new sources
apt update

# libjpeg62-turbo-dev
apt install --no-install-recommends -y \
        libjpeg62-turbo-dev
## libjpeg-turbo is faster than libjpeg

# Dockerfile 35
apt install -t testing --no-install-recommends -yqq \
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
# apt install -t stable --no-install-recommends -y \
#         intel-media-va-driver