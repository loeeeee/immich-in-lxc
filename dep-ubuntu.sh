#!/bin/bash

set -xeuo pipefail # Make my life easier

# Install Dependency for Ubuntu 24.04 LTS

exec ./dep-common.sh

apt install -y \
        libio-compress-brotli-perl \
        libwebp-dev \
        libdav1d-dev \
        libjxl-dev
