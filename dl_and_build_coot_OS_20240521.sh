#!/bin/sh

error () {
  [ $# -eq 0 ] && printf "\n ERROR: see above\n\n" || printf "\n ERROR: $@\n\n"
  exit 1
}
usage () {
  printf "\n USAGE: `basename $0` [-h] [-v] [-test]\n\n"
}

case `uname` in
  Linux) true;;
  *) error "running on a non-Linux system!";;
esac

if [ -f /etc/os-release ]; then
  os=`(. /etc/os-release ; echo "$NAME-${VERSION_ID}" | sed "s/ [^-]*-/-/g")`
elif [ -f /etc/lsb-release ]; then
  os=`(. /etc/lsb-release ; echo ${DISTRIB_ID}-${DISTRIB_RELEASE})`
elif [ -f /etc/SUSE-brand ]; then
  os=openSUSE
elif [ -f /etc/rocky-release ]; then
  os=Rocky
elif [ -f /etc/debian_version ]; then
  os=Debian
fi
[ "X$os" = "X" ] && error "unable to figure out OS version and/or Linux distro)!"

case `id -nu` in
  root) sudo="";;
  *) sudo=sudo;;
esac

iverb=0
while [ $# -gt 0 ]
do
   case $1 in
    -h|-help|--help)usage;exit 0;;
    -v)iverb=`expr $iverb + 1`;;
    -test)sudo="echo";;
    *) error "unknown argument = \"$1\"";;
  esac
  shift
done

[ $iverb -ge 1 ] && set -x

case `echo "$os" | tr '[A-Z]' '[a-z]'` in
    opensuse*)
      # probably not all needed:
      $sudo zypper -y install \
            -t pattern devel_basis || error
      # probably not all needed:
      $sudo zypper -y install \
             openssl-devel \
             gcc12-fortran \
             autoconf \
             automake \
             blas-devel \
             curl-devel \
             fdupes \
             fftw-devel \
             gcc12-c++ \
             glm-devel \
             gsl-devel \
             gtk4-devel \
             libboost_headers-devel-impl \
             libboost_iostreams-devel-impl \
             libboost_serialization-devel-impl \
             libboost_thread-devel-impl \
             libepoxy-devel \
             libicu-devel \
             libtool \
             sqlite3-devel \
             swig \
             libxml2-devel \
             libdrm-devel \
             || error
      ;;
    rocky*)
        $sudo yum -y install \
            gcc \
            gcc-c++ \
            gcc-gfortran \
            make \
            gcc-toolset-13 \
            gcc-toolset-12 \
            bzip2-devel \
            gperf \
            libX11-devel \
            libglvnd-devel \
            libffi-devel \
            freetype-devel \
            libcurl-devel \
            libxkbcommon-devel \
            libXrender-devel \
            libXext-devel \
            libXrandr-devel \
            libXi-devel \
            libXcursor-devel \
            libXdamage-devel \
            libXinerama-devel \
            libdrm-devel \
            || error
      ;;
    debian*|ubuntu*)
        # probably not all needed:
        $sudo apt-get -y install \
                build-essential \
                gfortran \
                libssl-dev \
                python3-openssl \
                git \
                flex \
                bison \
                gperf \
                libblas-dev \
                || error
        # probably not all needed (and requires deb-src settings):
        $sudo apt-get -y build-dep \
                python3 \
                libgtk-4-dev \
                libglib2.0-dev \
                pymol \
                || error
      ;;
    *) error "unsupported OS!";;
esac
