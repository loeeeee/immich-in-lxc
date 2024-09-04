#!/bin/bash

# Build dependencies

set -xeuo pipefail # Make people's life easier

# -------------------
# Common variables
# -------------------

SCRIPT_DIR=$PWD
REPO_URL="https://github.com/immich-app/base-images"
BASE_IMG_REPO_DIR=$SCRIPT_DIR/base-images

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

# -------------------
# Change build-lock permission
# -------------------

change_permission () {
    # Change file permission so that install script could copy the content
    chmod 666 $BASE_IMG_REPO_DIR/server/bin/build-lock.json
}

change_permission

# -------------------
# Build base images
# -------------------

build_base_images () {
    cd $SCRIPT_DIR

    # ImageMagick

    sed -i 's/build-lock.json/base-images\/server\/bin\/build-lock.json/g' ${BASE_IMG_REPO_DIR}/server/bin/build-imagemagick.sh 
    sed -i '/cd .. && rm -rf ImageMagick/d' ${BASE_IMG_REPO_DIR}/server/bin/build-imagemagick.sh

    exec $BASE_IMG_REPO_DIR/server/bin/build-imagemagick.sh
}

build_base_images