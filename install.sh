#!/bin/bash

set -xeuo pipefail # Make people's life easier

# -------------------
# Check current user
# -------------------

check_user_id () {
    if [ "$EUID" -eq 0 ]; then
        echo "Error: This script should NOT be run as root."
        exit 1
    fi
}

check_user_id

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
            echo "Please review the .env before rerunning the script"
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

set +x
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
    # npm dist proxy (used by node-gyp)
    echo $PROXY_NPM_DIST
    # poetry proxy
    echo $PROXY_POETRY
}

review_install_information

# -------------------
# Check if node are installed
# -------------------

install_node () {
    # node.js
    if ! command -v node &> /dev/null; then
        echo "ERROR: Node.js is not installed."
        echo "Installing Node.js for current user"
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
        \. "$HOME/.nvm/nvm.sh"
        # use $PROXY_NPM_DIST 
        NVM_NODEJS_ORG_MIRROR=$PROXY_NPM_DIST
        nvm install --lts
        echo "Finish installing latest LTS node"
    fi

    if ! command -v pnpm &> /dev/null; then
        echo "Installing pnpm"
        npm install -g pnpm@10
    fi

    echo "npm version: {$(npm -v)}"
    echo "node version: {$(node -v)}"
    echo "pnpm version: {$(pnpm -v)}"
}

install_node

# -------------------
# Check if dependency are met
# -------------------

review_dependency () {
    # ffmpeg
    if ! command -v ffmpeg &> /dev/null; then
        echo "ERROR: ffmpeg is not installed."
        echo "Please run pre-install.sh first"
        exit 1
    fi

    # node.js
    if ! command -v node &> /dev/null; then
        echo "ERROR: Node.js is not installed."
        exit 1
    fi

    # python3
    if ! command -v python3 &> /dev/null; then
        echo "ERROR: Python is not installed."
        exit 1
    fi

    # git
    if ! command -v git &> /dev/null; then
        echo "ERROR: Git is not installed."
        exit 1
    fi

    # (Optional) Nvidia Driver
    if [ $isCUDA = true ]; then
        if ! nvidia-smi &> /dev/null; then
            echo "ERROR: Nvidia driver is not installed, and isCUDA is set to true"
            exit 1
        fi
    fi

    echo "Dependency check passed!"
}

review_dependency

set -xeuo pipefail

# -------------------
# Common variables
# -------------------

INSTALL_DIR_src=$INSTALL_DIR/source
INSTALL_DIR_app=$INSTALL_DIR/app
INSTALL_DIR_ml=$INSTALL_DIR_app/machine-learning
INSTALL_DIR_geo=$INSTALL_DIR/geodata
TMP_DIR=/tmp/$(whoami)/immich-in-lxc/
REPO_URL="https://github.com/immich-app/immich"
MAJOR_VERSION=$(echo $REPO_TAG | cut -d'.' -f1) # No longer used, but might worth keeping it around
MINOR_VERSION=$(echo $REPO_TAG | cut -d'.' -f2) # No longer used, but might worth keeping it around

# The idea is that when one needs to sets up a proxy for NPM, 
# they might not have good access to GitHub
# Thus, build from source would be faster
# Add --build-from-source in npm ci is the solution if node-pre-gyp stuck at GET http https://github.com.....
# Lastly, printing out build process looks cool :)
if [ -n "$PROXY_NPM" ]; then
  isNPM_BUILD_FROM_SOURCE="true"
else
  isNPM_BUILD_FROM_SOURCE="false"
fi


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

    # Create a temporary folder for the json files
    mkdir -p $TMP_DIR
}

create_folders

# -------------------
# Clone the main repo
# -------------------

clone_the_repo () {
    if [ ! -d "$INSTALL_DIR_src" ]; then
        git clone "$REPO_URL" "$INSTALL_DIR_src" --single-branch
        cd $INSTALL_DIR_src
    else
        cd $INSTALL_DIR_src
        # REMOVE all the change one made to source repo, which is sth not supposed to happen
        git reset --hard main
        # In case one is not on the branch
        git checkout main
        # Get updates
        git pull
    fi
    # Set the install version
    git checkout $REPO_TAG
}

clone_the_repo

# -------------------
# Install immich-web-server
# -------------------

install_immich_web_server_pnpm () {
    cd $INSTALL_DIR_src

    # Set mirror for pnpm (if needed)
    if [ ! -z "${PROXY_NPM}" ]; then
        pnpm config set registry=$PROXY_NPM
    fi

    rm -r $INSTALL_DIR_app 

    # Install dependencies
    pnpm install --frozen-lockfile
    npm_config_sharp_binary_host="" SHARP_FORCE_GLOBAL_LIBVIPS=true pnpm install

    pnpm --filter immich --frozen-lockfile build
    pnpm --filter @immich/sdk --filter immich-web --frozen-lockfile build
    # Build and deploy the server component.
    pnpm --filter immich --prod deploy $INSTALL_DIR_app

    # Build and deploy the CLI.
    pnpm --filter @immich/cli --frozen-lockfile --prod --no-optional deploy $INSTALL_DIR_app/cli

    ln -s ../cli/bin/immich $INSTALL_DIR_app/bin/immich

    # Copy the built Web UI to the target directory.
    cp -a web/build $INSTALL_DIR_app/www

    cp -a LICENSE $INSTALL_DIR_app/
    cp -a i18n $INSTALL_DIR/
    cp -a server/bin/get-cpus.sh server/bin/start.sh $INSTALL_DIR_app/

    # Unset mirror for pnpm (if it was set)
    if [ ! -z "${PROXY_NPM}" ]; then
        pnpm config delete registry
    fi
}


install_immich_web_server () {
    cd $INSTALL_DIR_src

    # Set mirror for npm
    if [ ! -z "${PROXY_NPM}" ]; then
        npm config set registry=$PROXY_NPM
    fi
    # Set mirror for npm dist
    if [ ! -z "${PROXY_NPM_DIST}" ]; then
        export npm_config_dist_url=$PROXY_NPM_DIST
    fi
    # Set npm args
    if $isNPM_BUILD_FROM_SOURCE; then
        npm_args="--build-from-source --verbose --foreground-script"
    else
        npm_args=""
    fi

    # This solves fallback-to-build issue with bcrypt and utimes
    npm install -g node-gyp @mapbox/node-pre-gyp
    # Solve audit stuck by skipping it, [Additional info](https://overreacted.io/npm-audit-broken-by-design/)
    # npm config set audit false
    # Install immich cli
    npm i -g @immich/cli

    cd server
    npm ci $npm_args # --cpu x64 --os linux
    # From immich-app/server/Dockerfile line 7
    rm -rf $INSTALL_DIR_app/node_modules/@img/sharp-libvips*
    rm -rf $INSTALL_DIR_app/node_modules/@img/sharp-linuxmusl-x64
    # Install non-trivial dependency
    npm i exiftool-vendored.pl
    npm run build
    npm prune --omit=dev --omit=optional
    cd ..

    cd open-api/typescript-sdk
    npm ci $npm_args # --cpu x64 --os linux
    npm run build
    cd ../..

    cd web
    npm ci $npm_args # --cpu x64 --os linux
    npm run build
    cd ..

    # Unset mirror for npm
    if [ ! -z "${PROXY_NPM}" ]; then
        npm config delete registry
    fi

    cp -a server/node_modules server/dist server/bin $INSTALL_DIR_app/
    cp -a web/build $INSTALL_DIR_app/www
    cp -a server/resources server/package.json server/package-lock.json $INSTALL_DIR_app/
    cp -a server/bin/get-cpus.sh server/bin/start.sh $INSTALL_DIR_app/
    cp -a LICENSE $INSTALL_DIR_app/
    cp -a i18n $INSTALL_DIR/
    cp -a open-api/typescript-sdk $INSTALL_DIR_app/
    cd ..
}

install_immich_web_server_pnpm

# -------------------
# Generate build-lock
# -------------------

generate_build_lock () {
    # So that immich would not complain
    cd $SCRIPT_DIR

    cd base-images/server/

    # From base-images/server/Dockerfile line 110
    jq -s '.' packages/*.json > $TMP_DIR/packages.json
    jq -s '.' sources/*.json > $TMP_DIR/sources.json
    jq -n \
        --slurpfile sources $TMP_DIR/sources.json \
        --slurpfile packages $TMP_DIR/packages.json \
        '{sources: $sources[0], packages: $packages[0]}' \
        > $INSTALL_DIR_app/build-lock.json
}

generate_build_lock

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
    pip3 install poetry -i $PROXY_POETRY

    # Set PROXY_POETRY as the primary source to download package from
    # https://python-poetry.org/docs/repositories/#primary-package-sources
    if [ ! -z "${PROXY_POETRY}" ]; then
        # langsam literally means slow
        poetry source add --priority=primary langsam $PROXY_POETRY
    fi

    # Deal with python 3.12
    python3_version=$(python3 --version 2>&1 | awk -F' ' '{print $2}' | awk -F'.' '{print $2}')
    if [ $python3_version = 12 ]; then
        # Allow Python 3.12 (e.g., Ubuntu 24.04)
        sed -i -e 's/<3.12/<4/g' pyproject.toml
        poetry update
    fi
    
    # Install CUDA parts only when necessary
    if [ $isCUDA = true ]; then
        poetry install --no-root --extras cuda
    elif [ $isCUDA = "openvino" ]; then
        poetry install --no-root --extras openvino
    elif [ $isCUDA = "rocm" ]; then
        # https://rocm.docs.amd.com/projects/radeon/en/latest/docs/install/native_linux/install-onnx.html
        pip3 install onnxruntime-rocm -f https://repo.radeon.com/rocm/manylinux/rocm-rel-6.4.1/
        # Verify installation
        python3 -c "import onnxruntime as ort; print(ort.get_available_providers())"
        # ROCm needs numpy < 2 [workaround](https://rocm.docs.amd.com/projects/radeon/en/latest/docs/install/native_linux/install-onnx.html)
        pip install "numpy<2" -i $PROXY_POETRY
    else
        poetry install --no-root --extras cpu
    fi

    # Reset the settings
    if [ ! -z "${PROXY_POETRY}" ]; then
        # Remove the source
        # https://python-poetry.org/docs/cli/#source-remove
        poetry source remove langsam
    fi

    )

    # Copy results
    cd $INSTALL_DIR_src
    cp -a machine-learning/ann machine-learning/immich_ml $INSTALL_DIR_ml/
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

    sed -i -e "s@\"/cache\"@\"$INSTALL_DIR/cache\"@g" $INSTALL_DIR_ml/immich_ml/config.py

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
    # Set npm args
    if $isNPM_BUILD_FROM_SOURCE; then
        npm_args="--verbose --foreground-script"
    else
        npm_args=""
    fi

    npm install --build-from-source $npm_args sharp

    # Remove sharp dependency so that it use system library


    # Unset mirror for npm
    if [ ! -z "${PROXY_NPM}" ]; then
        npm config delete registry
    fi
}

# install_sharp_and_cli

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

exec gunicorn immich_ml.main:app \
        -k immich_ml.config.CustomUvicornWorker \
        -w "\$MACHINE_LEARNING_WORKERS" \
        -b "\$MACHINE_LEARNING_HOST":"\$MACHINE_LEARNING_PORT" \
        -t "\$MACHINE_LEARNING_WORKER_TIMEOUT" \
        --log-config-json log_conf.json \
        --graceful-timeout 0
EOF

    chmod 775 $INSTALL_DIR_ml/start.sh
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
