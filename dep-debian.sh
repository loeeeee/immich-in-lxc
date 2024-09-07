#!/bin/bash

set -xeuo pipefail # Make my life easier

## From immich/base-image
apt install --no-install-recommends -y\
        autoconf \
        build-essential \
        cmake \
        jq \
        perl \
        libnet-ssleay-perl \
        libio-socket-ssl-perl \
        libcapture-tiny-perl \
        libfile-which-perl \
        libfile-chdir-perl \
        libpkgconfig-perl \
        libffi-checklib-perl \
        libtest-warnings-perl \
        libtest-fatal-perl \
        libtest-needs-perl \
        libtest2-suite-perl \
        libsort-versions-perl \
        libpath-tiny-perl \
        libtry-tiny-perl \
        libterm-table-perl \
        libany-uri-escape-perl \
        libmojolicious-perl \
        libfile-slurper-perl \
        libde265-dev \
        libexif-dev \
        libexpat1-dev \
        libglib2.0-dev \
        libgsf-1-dev \
        libjxl-dev \
        liblcms2-2 \
        liborc-0.4-dev \
        librsvg2-dev \
        libspng-dev \
        meson \
        ninja-build \
        pkg-config \
        wget \
        zlib1g \
        cpanminus \
        libltdl-dev

# Needs to run base-images/server/bin/configure-apt.sh first
apt install -t testing -y \
        libdav1d-dev \
        libjxl-dev \
        libwebp-dev \
        libio-compress-brotli-perl

apt install -y libgdk-pixbuf-2.0-dev librsvg2-dev libtool

## For additional functionality
apt install --no-install-recommends -y \
        ca-certificates \
        libde265-0 \
        libexif12 \
        libexpat1 \
        libgcc-s1 \
        libglib2.0-0 \
        libgomp1 \
        libgsf-1-114 \
        libjxl0.7 \
        liblcms2-2 \
        liblqr-1-0 \
        libltdl7 \
        libmimalloc2.0 \
        libopenexr-3-1-30 \
        libopenjp2-7 \
        liborc-0.4-0 \
        librsvg2-2 \
        libspng0 \
        mesa-utils \
        mesa-va-drivers \
        mesa-vulkan-drivers \
        tini \
        zlib1g \
        libwebp7 \
        libwebpdemux2 \
        libwebpmux3