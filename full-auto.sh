#!/bin/bash

# This script is only for the purpose of testing, do not use it beyond the purpse of testing!

# This script is intended for testing on Ubuntu 24 LTS

# This script is indended to be run as root

# Planned supported env variable:
# NVM_NODEJS_ORG_MIRROR
# isCUDA
# PROXY_NPM
# PROXY_POETRY
# RESET

set -xeuo pipefail # Make people's life easier

# Reset things
while getopts "Rr" opt; do
    case $opt in
        R)
        # Less soft reset
        apt purge -yqq postgresql-17 postgresql-17-pgvector
        apt purge -y jellyfin-ffmpeg6
        rm /usr/bin/ffmpeg /usr/bin/ffprobe
        rm /etc/apt/keyrings/jellyfin.gpg
        rm /etc/apt/sources.list.d/jellyfin.sources
        apt purge -y redis
        deluser --remove-all-files immich
        apt update
        exit 0
        ;;
        r)
        # Soft reset
        deluser immich
        rm /usr/bin/ffmpeg /usr/bin/ffprobe
        rm /etc/apt/keyrings/jellyfin.gpg
        rm /etc/apt/sources.list.d/jellyfin.sources
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
apt install -y jellyfin-ffmpeg7

ln -s /usr/lib/jellyfin-ffmpeg/ffmpeg  /usr/bin/ffmpeg
ln -s /usr/lib/jellyfin-ffmpeg/ffprobe  /usr/bin/ffprobe

# Redis

apt install -y redis

# Immich user

adduser --shell /bin/bash --disabled-password immich --comment "Immich Mich"

# Git repos

if [ ! -d "/home/immich/immich-in-lxc" ]; then
    sudo -u immich -s -n -- git clone https://github.com/loeeeee/immich-in-lxc.git /home/immich/immich-in-lxc
fi

# Dependency

./dep-ubuntu.sh

# Pre-install

./pre-install.sh

# NPM

su immich -c sh -c "cd /home/immich && curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash"
sudo -u immich -s -n -E -- ". /home/immich/.nvm/nvm.sh && nvm install 20"

# Immich

## Generate config
sudo -u immich -s -n -E -- "cd /home/immich/immich-in-lxc && ./install.sh"
## Load environment variables
assign_to_file() {
    env_var=$2
    file_path=/home/immich/immich-in-lxc/.env

    # Check if environment variable exists and has a value
    if [[ -n "${!env_var}" ]]; then
    # Check if the environment variable already exists in the file
        if grep -q "^${env_var}=" "$file_path"; then
            echo "Environment variable $env_var already exists in $file_path"
        else
            # Write the value to the file
            echo "${env_var}=${!env_var}" >> "$file_path"
            echo "Assigned value to $file_path"
        fi
    else
        echo "Environment variable $env_var not found or empty"
    fi
}
## Install
sudo -u immich -s -n -E -- "cd /home/immich/immich-in-lxc && ./install.sh"

# Post-install

./post-install.sh

# Start Immich

systemctl daemon-reload
systemctl start immich-microservices
systemctl start immich-ml
systemctl start immich-web