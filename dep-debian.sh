#!/bin/bash

set -xeuo pipefail # Make my life easier

# Install dependencys for Debian 12

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

# Install dev libraries from testing
apt install -t testing --no-install-recommends -yqq \
        libhwy-dev \
        libsharpyuv-dev \
        libwebp-dev