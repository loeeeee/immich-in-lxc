#!/bin/bash

# Build dependencies

set -xeuo pipefail # Make people's life easier

# -------------------
# Common variables
# -------------------

SCRIPT_DIR=$PWD
REPO_URL="https://github.com/immich-app/base-images"
BASE_IMG_REPO_DIR=$SCRIPT_DIR/base-images
SOURCE_DIR=$SCRIPT_DIR/image-source

# -------------------
# Git clone function
# -------------------

function git_clone () {
    # $1 is repo URL
    # $2 is clone target folder
    # $3 is branch name
    if [ ! -d "$2" ]; then
        git clone "$1" "$2"
    fi
    cd $2
    # REMOVE all the change one made to source repo, which is sth not supposed to happen
    git reset --hard $3
    # In case one is not on the branch
    git checkout $3
    # Get updates
    git pull
}

# -------------------
# Clone the base images repo
# -------------------

git_clone $REPO_URL $BASE_IMG_REPO_DIR main

# -------------------
# Change build-lock permission
# -------------------

change_permission () {
    # Change file permission so that install script could copy the content
    chmod 666 $BASE_IMG_REPO_DIR/server/bin/build-lock.json
}

change_permission

# -------------------
# Setup folders
# -------------------

setup_folders () {
    cd $SCRIPT_DIR

    if [ ! -d "$SOURCE_DIR" ]; then
        mkdir $SOURCE_DIR
    fi
}

setup_folders

# -------------------
# Build image magick
# -------------------

build_image_magick () {
    cd $SCRIPT_DIR

    SOURCE=$SOURCE_DIR/image-magick

    set -e
    : "${IMAGEMAGICK_REVISION:=$(jq -cr '.sources[] | select(.name == "imagemagick").revision' $BASE_IMG_REPO_DIR/server/bin/build-lock.json)}"
    set +e

    git_clone https://github.com/ImageMagick/ImageMagick.git $SOURCE $IMAGEMAGICK_REVISION

    cd $SOURCE

    ./configure --with-modules
    make -j$(nproc)
    make install
    ldconfig /usr/local/lib
}

build_image_magick