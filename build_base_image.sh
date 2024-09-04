#!/bin/bash

# This script is expected to be runned at ./immich-in-lxc

# ImageMagick

sed -i 's/build-lock.json/base-images\/server\/bin\/build-lock.json/g' base-images/server/bin/build-imagemagick.sh 
sed -i '/cd .. && rm -rf ImageMagick/d' base-images/server/bin/build-imagemagick.sh

./base-images/server/bin/build-imagemagick.sh 
