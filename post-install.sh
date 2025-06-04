#!/bin/bash

set -xeuo pipefail # Make my life easier

# -------------------
# Copy service file
# -------------------
SCRIPT_DIR=$PWD

copy_service_files () {
    # Remove deprecated service
    rm -f /etc/systemd/system/immich-microservices.service
    # Copy new services
    cp --update=none immich-ml.service /etc/systemd/system/
    cp --update=none immich-web.service /etc/systemd/system/
}

copy_service_files

# -------------------
# Create log directory
# -------------------

create_log_directory () {
    mkdir -p /var/log/immich
}

create_log_directory

echo "Done!"


# -------------------
# Remove build dependency
# -------------------

remove_build_dependency () {
    apt-get remove -y \
        libbrotli-dev \
        libde265-dev \
        libexif-dev \
        libexpat1-dev \
        libgsf-1-dev \
        liblcms2-2 \
        librsvg2-dev \
        libspng-dev
    apt-get remove -y \
        libdav1d-dev \
        libhwy-dev \
        libwebp-dev \
        libio-compress-brotli-perl
}

remove_build_dependency

# -------------------
# Remove build dependency
# -------------------

add_runtime_dependency () {
     apt-get install --no-install-recommends -yqq \
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
    apt-get install --no-install-recommends -y \
        libio-compress-brotli-perl \
        libwebp7 \
        libwebpdemux2 \
        libwebpmux3 \
        libhwy1t64
}

add_runtime_dependency
