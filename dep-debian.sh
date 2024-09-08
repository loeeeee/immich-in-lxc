#!/bin/bash

set -xeuo pipefail # Make my life easier

# Install Dependency for Debian 12

./dep-common.sh

apt install -t testing -y \
        libio-compress-brotli-perl \
        libwebp-dev \
        libdav1d-dev \
        libjxl-dev
