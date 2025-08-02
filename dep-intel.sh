#!/bin/bash

set -xeuo pipefail # Make my life easier

# :warning: This script is only needed for those would like to use Intel/OpenVINO ONNX execution provider.

# Variables
TEMP_DIR=/tmp/immich-intel

mkdir $TEMP_DIR
cd $TEMP_DIR

# Copied from immich/machine-learning/Dockerfile line 77
apt-get install --no-install-recommends -yqq ocl-icd-libopencl1 wget
wget -nv https://github.com/intel/intel-graphics-compiler/releases/download/igc-1.0.17384.11/intel-igc-core_1.0.17384.11_amd64.deb
wget -nv https://github.com/intel/intel-graphics-compiler/releases/download/igc-1.0.17384.11/intel-igc-opencl_1.0.17384.11_amd64.deb
wget -nv https://github.com/intel/compute-runtime/releases/download/24.31.30508.7/intel-opencl-icd_24.31.30508.7_amd64.deb
wget -nv https://github.com/intel/compute-runtime/releases/download/24.31.30508.7/libigdgmm12_22.4.1_amd64.deb
dpkg -i *.deb

# Clean up
rm -r $TEMP_DIR

echo "All Good"