#!/bin/bash

set -xeuo pipefail # Make my life easier

# -------------------
# Copy service file
# -------------------
SCRIPT_DIR=$PWD


# -------------------
# Load environment variables from env file
# -------------------

load_environment_variables () {
    # Read the .env file into variables
    cd $SCRIPT_DIR
    set -a
    . ./.env
    set +a
}

load_environment_variables

copy_service_files () {
    # Remove deprecated service
    rm -f /etc/systemd/system/immich-microservices.service
    # Copy new services
    cp immich-ml.service /etc/systemd/system/
    MINOR_VERSION=$(echo $REPO_TAG | cut -d'.' -f2)
    if [ $MINOR_VERSION -gt 130 ]; then
        sed -i -e '0,/^WorkingDirectory/ s,^WorkingDirectory.*,WorkingDirectory=/home/immich/app/machine-learning,' \
               -e "0,/^ExecStart/ s,^ExecStart.*,ExecStart=/bin/bash -c 'source /home/immich/app/machine-learning/venv/bin/activate \&\& python -m immich_ml'," \
               /etc/systemd/system/immich-ml.service
    fi
    cp immich-web.service /etc/systemd/system/
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
