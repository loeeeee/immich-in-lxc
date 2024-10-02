#!/bin/bash

# This script is only for the purpose of testing, do not use it beyond the purpse of testing!

# This script is intended for testing on Ubuntu 24 LTS

# This script is indended to be run as root

# Supported env variable:
# NVM_NODEJS_ORG_MIRROR
# isCUDA
# PROXY_NPM
# PROXY_POETRY
# RESET

set -xeuo pipefail # Make people's life easier

# Reset things
while getopts "R" opt; do
    case $opt in
        R)
        apt purge -yqq postgresql-17 postgresql-17-pgvector
        apt purge -y jellyfin-ffmpeg6
        rm /usr/bin/ffmpeg /usr/bin/ffprobe
        rm /etc/apt/keyrings/jellyfin.gpg
        rm /etc/apt/sources.list.d/jellyfin.sources
        apt purge -y redis
        userdel immich
        apt update
        exit 0
        ;;
        \?)
        echo "Invalid option: -$OPTARG" >&2
        exit 1
        ;;
    esac
done

# Initalial update

apt update
apt upgrade -y 

# Postgres

apt install -y postgresql-common
/usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y
apt install -y postgresql-17
apt install -y postgresql-17-pgvector

sudo -u postgres -s -n -- psql << EOF
CREATE DATABASE immich;
CREATE USER immich WITH ENCRYPTED PASSWORD 'A_SEHR_SAFE_PASSWORD';
GRANT ALL PRIVILEGES ON DATABASE immich to immich;
ALTER USER immich WITH SUPERUSER;
EOF

# FFmpeg

apt install -y curl gnupg software-properties-common
add-apt-repository -y universe
mkdir -p /etc/apt/keyrings
curl -fsSL https://repo.jellyfin.org/jellyfin_team.gpg.key | gpg --dearmor -o /etc/apt/keyrings/jellyfin.gpg
export VERSION_OS="$( awk -F'=' '/^ID=/{ print $NF }' /etc/os-release )"
export VERSION_CODENAME="$( awk -F'=' '/^VERSION_CODENAME=/{ print $NF }' /etc/os-release )"
export DPKG_ARCHITECTURE="$( dpkg --print-architecture )"
cat <<EOF | tee /etc/apt/sources.list.d/jellyfin.sources
Types: deb
URIs: https://repo.jellyfin.org/${VERSION_OS}
Suites: ${VERSION_CODENAME}
Components: main
Architectures: ${DPKG_ARCHITECTURE}
Signed-By: /etc/apt/keyrings/jellyfin.gpg
EOF

apt update
apt install -y jellyfin-ffmpeg6

ln -s /usr/lib/jellyfin-ffmpeg/ffmpeg  /usr/bin/ffmpeg
ln -s /usr/lib/jellyfin-ffmpeg/ffprobe  /usr/bin/ffprobe

# Redis

apt install -y redis

# Git

apt install -y git

# Immich user

useradd -m immich
chsh -s /bin/bash immich

# Locale

sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen

# Git repos

sudo -u immich -s -n -- cd /home/immich/ && git clone https://github.com/loeeeee/immich-in-lxc.git

# Dependency

./dep-ubuntu.sh

# Pre-install

./pre-install.sh

# NPM

sudo -u immich -s -n -E -- cd /home/immich && curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash && nvm install 20

# Immich

## Generate config
sudo -u immich -s -n -E -- cd /home/immich/immich-in-lxc && ./install.sh
## Install
sudo -u immich -s -n -E -- cd /home/immich/immich-in-lxc && ./install.sh

# Post-install

./post-install.sh

# Start Immich

systemctl daemon-reload
systemctl start immich-microservices
systemctl start immich-ml
systemctl start immich-web