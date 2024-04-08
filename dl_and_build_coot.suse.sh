#!/usr/bin/bash

# This script is meant to run on OpenSUSE Leap 15 Docker image

export GCC_COMPILER_VERSION=13

install_dependencies_with_distro_package_manager() {
  zypper update -y
  zypper install -y \
      git wget gcc13 gcc13-c++ gcc13-fortran pkg-config gettext-runtime gettext-tools bison flex make automake gperf vim xmlto libtool gzip bzip2 \
      dbus-1-devel libmount-devel libexpat-devel libffi-devel libelf-devel libxml2-devel libxml2-tools readline-devel \
      libopenssl-devel libcurl-devel ncurses-devel sqlite3-devel lzo-devel libbz2-devel libpng16-devel libbrotli-devel libtiff-devel \
      libxcb-devel \
      Mesa-libEGL-devel \
      libXrender-devel xcb-util-renderutil-devel libXext-devel libXrandr-devel libXi-devel libXcursor-devel \
      libXdamage-devel libXinerama-devel \
      libxkbcommon-devel libxkbcommon-x11-devel xcb-util-devel xcb-proto-devel libX11-devel  \
      libopenblas_pthreads-devel gmp-devel gc-devel libunistring-devel pcre2-devel libdrm-devel glm-devel \
      fftw3-devel fftw3-threads-devel libglfw-devel \
      bc
}
