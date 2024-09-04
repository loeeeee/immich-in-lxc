#!/bin/bash

set -xeuo pipefail # Make people's life easier

# -------------------
# Create env file if it does not exists
# -------------------
SCRIPT_DIR=$PWD

create_install_env_file () {
    # Check if env file exists
    if [ ! -f $SCRIPT_DIR/.env ]; then
        # If not, create a new one based on the template
        if [ -f $SCRIPT_DIR/install.env ]; then
            cp install.env .env
            echo "New .env file created from the template, exiting"
            exit 0
        else
            echo ".env.template not found, please clone the entire repo, exiting"
            exit 1
        fi
    fi
}

create_install_env_file

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

# -------------------
# Review environment variables
# -------------------

review_install_information () {
    # Install Version
    echo $REPO_TAG
    # Install Location
    echo $INSTALL_DIR
    # Upload Location
    echo $UPLOAD_DIR
    # Cuda or CPU
    echo $isCUDA
    # npm proxy
    echo $PROXY_NPM
    # poetry proxy
    echo $PROXY_POETRY
}

review_install_information

# -------------------
# Check if dependency are met
# -------------------

review_dependency () {
    # ffmpeg
    if ! command -v ffmpeg &> /dev/null; then
        echo "ERROR: ffmpeg is not installed."
    fi

    # node.js
    if ! command -v node &> /dev/null; then
        echo "ERROR: Node.js is not installed."
    fi

    # python3
    if ! command -v python3 &> /dev/null; then
        echo "ERROR: Python is not installed."
    fi

    # git
    if ! command -v git &> /dev/null; then
        echo "ERROR: Git is not installed."
    fi

    # (Optional) Nvidia Driver
    if [ $isCUDA = true ]; then
        if ! nvidia-smi &> /dev/null; then
            echo "ERROR: Nvidia driver is not installed, and isCUDA is set to true"
            exit 1
        fi
    fi

    # (Optional) Nvidia CuDNN
}

review_dependency

# -------------------
# Common variables
# -------------------

BASE_IMG_REPO_DIR=$SCRIPT_DIR/base-images
INSTALL_DIR_src=$INSTALL_DIR/source
INSTALL_DIR_app=$INSTALL_DIR/app
INSTALL_DIR_ml=$INSTALL_DIR_app/machine-learning
INSTALL_DIR_geo=$INSTALL_DIR/geodata
REPO_URL="https://github.com/immich-app/immich"

# -------------------
# Clean previous build
# -------------------

clean_previous_build () {
    rm -rf $INSTALL_DIR_app
}

clean_previous_build

# -------------------
# Common variables
# -------------------

create_folders () {
    # No need to create source folder
    mkdir -p $INSTALL_DIR_app

    # Machine learning component
    mkdir -p $INSTALL_DIR_ml

    # Upload directory
    if [ ! -d "$UPLOAD_DIR" ]; then
        echo "$UPLOAD_DIR does not exists, creating one"
        mkdir -p $UPLOAD_DIR
    else
        echo "$UPLOAD_DIR already exists, skip creation"
    fi

    # GeoNames
    mkdir -p $INSTALL_DIR_geo
}

create_folders

# -------------------
# Clone the base images repo
# -------------------

clone_the_base_images_repo () {
    if [ ! -d "$BASE_IMG_REPO_DIR" ]; then
        git clone "$REPO_URL" "$BASE_IMG_REPO_DIR"
    fi

    cd $BASE_IMG_REPO_DIR
    # REMOVE all the change one made to source repo, which is sth not supposed to happen
    git reset --hard main
    # In case one is not on the branch
    git checkout main
    # Get updates
    git pull
}

clone_the_base_images_repo

exit 0

# -------------------
# Clone the main repo
# -------------------

clone_the_main_repo () {
    if [ ! -d "$INSTALL_DIR_src" ]; then
        git clone "$REPO_URL" "$INSTALL_DIR_src"
    fi

    cd $INSTALL_DIR_src
    # REMOVE all the change one made to source repo, which is sth not supposed to happen
    git reset --hard main
    # In case one is not on the branch
    git checkout main
    # Get updates
    git pull
    # Set the install version
    git checkout $REPO_TAG
}

clone_the_main_repo

# -------------------
# Install immich-web-server
# -------------------

install_immich_web_server () {
    cd $INSTALL_DIR_src

    # Set mirror for npm
    if [ ! -z "${PROXY_NPM}" ]; then
        npm config set registry=$PROXY_NPM
    fi

    cd server
    npm ci
    npm run build
    npm prune --omit=dev --omit=optional
    cd ..

    cd open-api/typescript-sdk
    npm ci
    npm run build
    cd ../..

    cd web
    npm ci
    npm run build
    cd ..

    # Unset mirror for npm
    if [ ! -z "${PROXY_NPM}" ]; then
        npm config delete registry
    fi

    cp -a server/node_modules server/dist server/bin $INSTALL_DIR_app/
    cp -a web/build $INSTALL_DIR_app/www
    cp -a server/resources server/package.json server/package-lock.json $INSTALL_DIR_app/
    cp -a server/start*.sh $INSTALL_DIR_app/
    cp -a LICENSE $INSTALL_DIR_app/
    cd ..
}

install_immich_web_server

# -------------------
# Install Immich-machine-learning
# -------------------

install_immich_machine_learning () {
    cd $INSTALL_DIR_src/machine-learning
    python3 -m venv $INSTALL_DIR_ml/venv
    (
    # Initiate subshell to setup venv
    . $INSTALL_DIR_ml/venv/bin/activate

    # Use pypi if proxy does not present
    if [ -z "${PROXY_POETRY}" ]; then
        PROXY_POETRY=https://pypi.org/simple/
    fi
    export POETRY_PYPI_MIRROR_URL=$PROXY_POETRY
    pip3 install poetry -i $PROXY_POETRY

    # Deal with python 3.12
    python3_version=$(python3 --version 2>&1 | awk -F' ' '{print $2}' | awk -F'.' '{print $2}')
    if [ $python3_version = 12 ]; then
        # Allow Python 3.12 (e.g., Ubuntu 24.04)
        sed -i -e 's/<3.12/<4/g' pyproject.toml
        poetry update
    fi

    # Install CUDA parts only when necessary
    if [ $isCUDA = true ]; then
        poetry install --no-root --with dev --with cuda
    else
        poetry install --no-root --with dev --with cpu
    fi

    # Work around for bad poetry config
    pip install "numpy<2" -i $PROXY_POETRY
    )
    
    # Copy results
    cd $INSTALL_DIR_src
    cp -a machine-learning/ann machine-learning/start.sh machine-learning/app $INSTALL_DIR_ml/
}

install_immich_machine_learning

# -------------------
# Replace /usr/src
# -------------------

# Honestly, I do not understand what does this part of the script does.

replace_usr_src () {
    cd $INSTALL_DIR_app
    grep -Rl /usr/src | xargs -n1 sed -i -e "s@/usr/src@$INSTALL_DIR@g"
    ln -sf $INSTALL_DIR_app/resources $INSTALL_DIR/
    mkdir -p $INSTALL_DIR/cache
    sed -i -e "s@\"/cache\"@\"$INSTALL_DIR/cache\"@g" $INSTALL_DIR_ml/app/config.py
    grep -RlE "\"/build\"|'/build'" | xargs -n1 sed -i -e "s@\"/build\"@\"$INSTALL_DIR_app\"@g" -e "s@'/build'@'$INSTALL_DIR_app'@g"
}

replace_usr_src

# -------------------
# Install sharp and CLI
# -------------------

install_sharp_and_cli () {
    cd $INSTALL_DIR_app

    # Set mirror for npm
    if [ ! -z "${PROXY_NPM}" ]; then
        npm config set registry=$PROXY_NPM
    fi

    npm install sharp

    npm i -g @immich/cli

    # Unset mirror for npm
    if [ ! -z "${PROXY_NPM}" ]; then
        npm config delete registry
    fi
}

install_sharp_and_cli

# -------------------
# Setup upload directory
# -------------------

setup_upload_folder () {
    ln -s $UPLOAD_DIR $INSTALL_DIR_app/upload
    ln -s $UPLOAD_DIR $INSTALL_DIR_ml/upload
}

setup_upload_folder

# -------------------
# Download GeoNames
# -------------------

download_geonames () {
    cd $INSTALL_DIR_geo
    if [ ! -f "cities500.zip" ] || [ ! -f "admin1CodesASCII.txt" ] || [ ! -f "admin2Codes.txt" ] || [ ! -f "ne_10m_admin_0_countries.geojson" ]; then
        echo "incomplete geodata, start downloading"
        wget -o - https://download.geonames.org/export/dump/admin1CodesASCII.txt &
        wget -o - https://download.geonames.org/export/dump/admin2Codes.txt &
        wget -o - https://download.geonames.org/export/dump/cities500.zip &
        wget -o - https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_10m_admin_0_countries.geojson &
        wait
        unzip cities500.zip
        date --iso-8601=seconds | tr -d "\n" > geodata-date.txt
    else
        echo "geodata exists, skip downloading"
    fi

    cd $INSTALL_DIR
    # Link the folder
    ln -s $INSTALL_DIR_geo $INSTALL_DIR_app/
}

download_geonames

# -------------------
# Create custom start.sh script
# -------------------

create_custom_start_script () {
    # Immich web and microservices
    cat <<EOF > $INSTALL_DIR_app/start.sh
#!/bin/bash

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

set -a
. $INSTALL_DIR/runtime.env
set +a

cd $INSTALL_DIR_app
exec node $INSTALL_DIR_app/dist/main "\$@"
EOF

    # Machine learning
    cat <<EOF > $INSTALL_DIR_ml/start.sh
#!/bin/bash

set -a
. $INSTALL_DIR/runtime.env
set +a

cd $INSTALL_DIR_ml
. venv/bin/activate

: "\${MACHINE_LEARNING_HOST:=127.0.0.1}"
: "\${MACHINE_LEARNING_PORT:=3003}"
: "\${MACHINE_LEARNING_WORKERS:=1}"
: "\${MACHINE_LEARNING_WORKER_TIMEOUT:=120}"

exec gunicorn app.main:app \
        -k app.config.CustomUvicornWorker \
        -w "\$MACHINE_LEARNING_WORKERS" \
        -b "\$MACHINE_LEARNING_HOST":"\$MACHINE_LEARNING_PORT" \
        -t "\$MACHINE_LEARNING_WORKER_TIMEOUT" \
        --log-config-json log_conf.json \
        --graceful-timeout 0
EOF
}

create_custom_start_script

# -------------------
# Create runtime environment file
# -------------------

create_runtime_env_file () {
    cd $INSTALL_DIR
    # Check if env file exists
    if [ ! -f runtime.env ]; then
        # If not, create a new one based on the template
        if [ -f $SCRIPT_DIR/runtime.env ]; then
            cp $SCRIPT_DIR/runtime.env runtime.env
            echo "New runtime.env file created from the template, exiting"
        else
            echo "runtime.env not found, please clone the entire repo, exiting"
            exit 1
        fi
    fi
}

create_runtime_env_file

echo "----------------------------------------------------------------"
echo "Done. Please install the systemd services to start using Immich."
echo "----------------------------------------------------------------"