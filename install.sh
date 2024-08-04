#!/bin/bash

set -xeuo pipefail # Make people's life easier

# -------------------
# Create env file if it does not exists
# -------------------

create_local_env_file () {
    # Check if env file exists
    if [ ! -f .env ]; then
        # If not, create a new one based on the template
        if [ -f .env.template ]; then
            cp .env.template .env
            echo "New .env file created from the template, exiting"
            exit 0
        else
            echo ".env.template not found, please clone the entire repo, exiting"
            exit 1
        fi
    fi
}

create_local_env_file

# -------------------
# Load environment variables from env file
# -------------------

load_environment_variables () {
    # Read the .env file into variables
    while IFS= read -r line
    do
    if [[ $line =~ ^([A-Za-z0-9_]+)=(.*)$ ]]; then
        declare -g ${BASH_REMATCH[1]}="${BASH_REMATCH[2]}"
    fi
    done < .env
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

IMMICH_INSTALL_PATH=/var/lib/immich
IMMICH_INSTALL_PATH_APP=$IMMICH_INSTALL_PATH/app
INSTALL_DIR_app=$INSTALL_DIR/app

# -------------------
# Clean previous build
# -------------------

clean_previous_build () {
    # BASEDIR=$(dirname "$0")

    rm -rf $INSTALL_DIR_app
    mkdir -p $INSTALL_DIR_app

    # Wipe npm, pypoetry, etc
    # This expects immich user's home directory to be on $IMMICH_INSTALL_PATH/home
    rm -rf $INSTALL_DIR/home
    mkdir -p $INSTALL_DIR/home
}

# clean_previous_build

# -------------------
# Clone the repo
# -------------------

INSTALL_DIR_src=$INSTALL_DIR/source
REPO_BASE=$INSTALL_DIR/source
REPO_URL="https://github.com/immich-app/immich"
clone_the_repo () {
    if [ ! -d "$INSTALL_DIR_src" ]; then
        git clone "$REPO_URL" "$INSTALL_DIR_src"
    fi

    cd $INSTALL_DIR_src
    git reset --hard $REPO_TAG
}
exit 0

# -------------------
# Install immich-web-server
# -------------------

install_immich_web_server () {
    cd $INSTALL_DIR_src

    cd server
    npm ci
    npm run build
    npm prune --omit=dev --omit=optional
    cd -

    cd open-api/typescript-sdk
    npm ci
    npm run build
    cd -

    cd web
    npm ci
    npm run build
    cd -

    cp -a server/node_modules server/dist server/bin $INSTALL_DIR_app/
    cp -a web/build $INSTALL_DIR_app/www
    cp -a server/resources server/package.json server/package-lock.json $INSTALL_DIR_app/
    cp -a server/start*.sh $INSTALL_DIR_app/
    cp -a LICENSE $INSTALL_DIR_app/
    cd $INSTALL_DIR_app
    # npm cache clean --force
    cd -
}

install_immich_web_server

# -------------------
# Install Immich-machine-learning
# -------------------

install_immich_machine_learning () {
    IMMICH_MACHINE_LEARNING_PATH=$IMMICH_INSTALL_PATH_APP/machine-learning
    mkdir -p $IMMICH_MACHINE_LEARNING_PATH
    python3 -m venv $IMMICH_MACHINE_LEARNING_PATH/venv
    (
    # Initiate subshell to setup venv
    . $IMMICH_MACHINE_LEARNING_PATH/venv/bin/activate
    pip3 install poetry
    cd machine-learning
    export POETRY_PYPI_MIRROR_URL=https://mirror.sjtu.edu.cn/pypi/web/simple
    if false; then # Set this to true to force poetry update
        # Allow Python 3.12 (e.g., Ubuntu 24.04)
        sed -i -e 's/<3.12/<4/g' pyproject.toml
        poetry update
    fi
    poetry install --no-root --with dev --with cuda
    cd ..
    )
    cp -a machine-learning/ann machine-learning/start.sh machine-learning/app $IMMICH_MACHINE_LEARNING_PATH/
}

install_immich_machine_learning

# -------------------
# Replace /usr/src
# -------------------

# Honestly, I do not understand what does this part of the script does.

replace_usr_src () {
    cd $IMMICH_INSTALL_PATH_APP
    grep -Rl /usr/src | xargs -n1 sed -i -e "s@/usr/src@$IMMICH_INSTALL_PATH@g"
    ln -sf $IMMICH_INSTALL_PATH/app/resources $IMMICH_INSTALL_PATH/
    mkdir -p $IMMICH_INSTALL_PATH/cache
    sed -i -e "s@\"/cache\"@\"$IMMICH_INSTALL_PATH/cache\"@g" $IMMICH_MACHINE_LEARNING_PATH/app/config.py
}

replace_usr_src

# -------------------
# Install sharp
# -------------------

install_sharp () {
    cd $IMMICH_INSTALL_PATH_APP
    npm install sharp
}

install_sharp

# -------------------
# Setup upload directory
# -------------------

setup_upload_folder () {
    mkdir -p $IMMICH_INSTALL_PATH/upload
    ln -s $IMMICH_INSTALL_PATH/upload $IMMICH_INSTALL_PATH_APP/
    ln -s $IMMICH_INSTALL_PATH/upload $IMMICH_MACHINE_LEARNING_PATH/
}

# Use 127.0.0.1
# sed -i -e "s@app.listen(port)@app.listen(port, '127.0.0.1')@g" $IMMICH_INSTALL_PATH_APP/dist/main.js

# -------------------
# Create custom start.sh script
# -------------------

create_custom_start_script () {
    cat <<EOF > $IMMICH_INSTALL_PATH_APP/start.sh
#!/bin/bash

set -a
. $IMMICH_INSTALL_PATH/env
set +a

cd $IMMICH_INSTALL_PATH_APP
exec node $IMMICH_INSTALL_PATH_APP/dist/main "\$@"
EOF

    cat <<EOF > $IMMICH_MACHINE_LEARNING_PATH/start.sh
#!/bin/bash

set -a
. $IMMICH_INSTALL_PATH/env
set +a

cd $IMMICH_MACHINE_LEARNING_PATH
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

# Cleanup
# rm -rf $REPO_BASE

echo
echo "Done. Please install the systemd services to start using Immich."
echo