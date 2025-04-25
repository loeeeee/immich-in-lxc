#!/bin/bash

set -xeuo pipefail # Make my life easier

# Because I removed one package
# apt --fix-broken -y install
# if [ -d "/tmp/immich-preinstall" ]; then
#     rm -r /tmp/immich-preinstall
# fi

# Install runtime component
## Redis
apt install --no-install-recommends -y\
        redis

# Install build dependency
## Tools
apt install --no-install-recommends -y\
        curl git python3-venv python3-dev unzip

## From immich/base-image
## libspng-dev is called libpng-dev on Ubuntu 22
apt install --no-install-recommends -y\
        autoconf \
        build-essential \
        cmake \
        jq \
        libbrotli-dev \
        libde265-dev \
        libexif-dev \
        libexpat1-dev \
        libglib2.0-dev \
        libgsf-1-dev \
        liblcms2-2 \
        librsvg2-dev \
        libspng-dev \
        meson \
        ninja-build \
        pkg-config \
        wget \
        zlib1g \
        cpanminus

## Learned from compile failure
apt install -y libgdk-pixbuf-2.0-dev librsvg2-dev libtool

## From libjxl guide
apt install -y --no-install-recommends libgif-dev libjpeg-dev libopenexr-dev libpng-dev libwebp-dev

# Install runtime dependency
apt install --no-install-recommends -y\
        ca-certificates \
        jq \
        libde265-0 \
        libexif12 \
        libexpat1 \
        libgcc-s1 \
        libglib2.0-0 \
        libgomp1 \
        libgsf-1-114 \
        liblcms2-2 \
        liblqr-1-0 \
        libltdl7 \
        libmimalloc2.0 \
        libopenexr-3-1-30 \
        libopenjp2-7 \
        librsvg2-2 \
        libspng0 \
        mesa-utils \
        mesa-va-drivers \
        mesa-vulkan-drivers \
        tini \
        wget \
        zlib1g \
        ocl-icd-libopencl1
