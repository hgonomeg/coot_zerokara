#!/usr/bin/bash

# This script is meant to run on Ubuntu 20.04 Docker image

export GCC_COMPILER_VERSION=10

install_dependencies_with_distro_package_manager() {
  export DEBIAN_FRONTEND=noninteractive  
  apt update
  apt install -y \
      git wget gcc-10 g++-10 gfortran-10 gettext pkg-config bison flex make automake gperf vim xmlto libtool-bin \
      xattr libdbus-1-dev libmount-dev libexpat1-dev libffi-dev libelf-dev libxml2-dev libxml2-utils libreadline-dev \
      libssl-dev libcurl4-openssl-dev libncurses-dev libsqlite3-dev liblzo2-dev libbz2-dev libpng-dev libbrotli-dev libtiff-dev \
      libxcb-glx0-dev \
      libegl1-mesa-dev \
      libxrender-dev libxcb-render0-dev libxcb-render-util0-dev libxext-dev libxrandr-dev libxi-dev libxcursor-dev \
      libxdamage-dev libxinerama-dev \
      libxkbcommon-x11-dev libxcb-shm0-dev libxcb-util-dev libxcb1-dev libx11-dev libxcb-dri3-dev libx11-xcb-dev \
      libopenblas-dev libgmp-dev libgc-dev libunistring-dev libpcre2-dev libdrm-dev libglm-dev \
      fftw-dev sfftw-dev libglfw3-dev \
      bc

}
