#!/bin/bash

set -xeuo pipefail # Make my life easier

# Install Dependency for Ubuntu 24.04 LTS

apt install --no-install-recommends -y \
        libjpeg-turbo8-dev

# Dockerfile 35
apt install --no-install-recommends -y \
        libdav1d-dev \
        libhwy-dev \
        libwebp-dev \
        libio-compress-brotli-perl

# Dockerfile 92
apt install --no-install-recommends -y \
        libio-compress-brotli-perl \
        libwebp7 \
        libwebpdemux2 \
        libwebpmux3 \
        libhwy1t64

# Dockerfile 104
apt install --no-install-recommends -y \
        intel-media-va-driver-non-free
