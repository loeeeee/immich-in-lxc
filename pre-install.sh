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
LD_LIBRARY_PATH=/usr/local/lib # :$LD_LIBRARY_PATH
LD_RUN_PATH=/usr/local/lib # :$LD_RUN_PATH

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
# Build libheif
# -------------------

build_libheif () {
    cd $SCRIPT_DIR

    SOURCE=$SOURCE_DIR/libheif

    set -e
    : "${LIBHEIF_REVISION:=$(jq -cr '.sources[] | select(.name == "libheif").revision' $BASE_IMG_REPO_DIR/server/bin/build-lock.json)}"
    set +e

    git_clone https://github.com/strukturag/libheif.git $SOURCE $LIBHEIF_REVISION

    cd $SOURCE

    mkdir build
    cd build
    cmake --preset=release-noplugins \
        -DWITH_DAV1D=ON \
        -DENABLE_PARALLEL_TILE_DECODING=ON \
        -DENABLE_LIBSHARPYUV=ON \
        -DENABLE_LIBDE265=ON \
        -DWITH_AOM_DECODER=OFF \
        -DWITH_AOM_ENCODER=OFF \
        -DWITH_X265=OFF \
        -DWITH_EXAMPLES=OFF \
        ..
    make install
    ldconfig /usr/local/lib

    # Clean up builds
    make clean
}

build_libheif

# -------------------
# Build libraw
# -------------------

build_libraw () {
    cd $SCRIPT_DIR

    SOURCE=$SOURCE_DIR/libraw

    set -e
    : "${LIBRAW_REVISION:=$(jq -cr '.sources[] | select(.name == "libraw").revision' $BASE_IMG_REPO_DIR/server/bin/build-lock.json)}"
    set +e

    git_clone https://github.com/libraw/libraw.git $SOURCE $LIBRAW_REVISION

    cd $SOURCE

    autoreconf --install
    ./configure
    make -j$(nproc)
    make install
    ldconfig /usr/local/lib

    # Clean up builds
    make clean
}

build_libraw

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

    # Clean up builds
    make clean
}

build_image_magick

# -------------------
# Build libvips
# -------------------

build_libvips () {
    cd $SCRIPT_DIR

    SOURCE=$SOURCE_DIR/libvips

    set -e
    : "${LIBVIPS_REVISION:=$(jq -cr '.sources[] | select(.name == "libvips").revision' $BASE_IMG_REPO_DIR/server/bin/build-lock.json)}"
    set +e

    git_clone https://github.com/libvips/libvips.git $SOURCE $LIBVIPS_REVISION

    cd $SOURCE

    meson setup build --buildtype=release --libdir=lib -Dintrospection=disabled -Dtiff=disabled
    cd build
    ninja install
    ldconfig /usr/local/lib
}

build_libvips
