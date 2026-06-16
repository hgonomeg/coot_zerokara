#!/bin/sh

my_version=1.0
#url_contrib="https://cloud.globalphasing.org/s/jC8RHNBfzmoxfL7"
url_contrib="https://cloud.globalphasing.org/public.php/dav/files/jC8RHNBfzmoxfL7/"

# -------------------------------------------------------------------------------------
# This script is meant to be run interactively: all download, building
# and installation is done in current directory

mypwd () {
  # Print cwd relative to $PREFIX when possible; fall back to absolute path
  # "X$PREFIX" != "X" is a POSIX-portable non-empty check (avoids issues with empty or flag-like values)
  if [ "X$PREFIX" != "X" ] && [ -d "$PREFIX" ]; then
    # ${PREFIX%/} strips a trailing slash so the pattern always has exactly one "/" separator
    # % is used as the sed delimiter instead of / to avoid escaping path separators in the pattern
    pwd | sed "s%^${PREFIX%/}/%%"
  else
    pwd
  fi
}

error () {
  [ $# -eq 0 ] && printf "\n ERROR: see above\n\n" || printf "\n ERROR: $@\n\n"
  if [ -f /etc/os-release ]; then
    cat /etc/os-release
  elif [ -f /etc/lsb-release ]; then
    cat /etc/lsb-release
  elif [ -f /etc/SUSE-brand ]; then
    cat /etc/SUSE-brand
  elif [ -f /etc/rocky-release ]; then
    cat /etc/rocky-release
  elif [ -f /etc/debian_version ]; then
    cat /etc/debian_version
  elif [ -f /etc/centos-release ]; then
    cat /etc/centos-release
  fi
  exit 1
}
warning () {
  [ $# -eq 0 ] && printf "\n WARNING: see above\n\n" || printf "\n WARNING: $@\n\n"
}

case `uname` in
  Linux) true;;
  *) error "running on a non-Linux system!";;
esac

# save current environment
env | sort > .env_start || error
umask 022

if [ -f /etc/os-release ]; then
  os=`(. /etc/os-release ; echo "$NAME-${VERSION_ID}" | sed "s/ [^-]*-/-/g")`
elif [ -f /etc/lsb-release ]; then
  os=`(. /etc/lsb-release ; echo ${DISTRIB_ID}-${DISTRIB_RELEASE})`
elif [ -f /etc/SUSE-brand ]; then
  warning "OpenSUSE version could not be determined"
  os=openSUSE
elif [ -f /etc/rocky-release ]; then
  warning "Rocky version could not be determined"
  os=Rocky
elif [ -f /etc/debian_version ]; then
  warning "Debian version obtained from /etc/debian_version"
  os="Debian-`head -n 1 /etc/debian_version | cut -f1 -d'/'`"
elif [ -f /etc/centos-release ]; then
  warning "CentOS version could not be determined"
  os=CentOS
else
  warning "Could not determine operating system distro/version!"
fi

usage () {
  printf "\n USAGE: `basename $0` [-h] [-v] [-nthreads <N>] [-fulltar] [-distributable] [-no-use-os-package-manager]\n"
  printf "\n  -h                          : this help message\n"
  printf "\n  -v                          : increase verbosity\n"
  printf "\n  -nthreads <N>               : set number of threads to use (where possible); default = use all\n"
  printf "\n  -fulltar                    : create \"full\" tarball at the end (static libs, docs, full refmac monomer library etc); default is a minimal tarball\n"
  printf "\n  -distributable              : build binaries for distribution (default is to tune for local machine/CPU)\n"
  printf "\n  -use-os-package-manager     : install required OS packages via the system package manager (DEFAULT; needs root/sudo)\n"
  printf "\n  -no-use-os-package-manager  : do NOT install OS packages\n"
  printf "\n  -noninteractive             : do not interactively ask for confirmation\n"
  printf "\n  -tag <tag>                  : Coot tag (for specific release; default = \"$COOT_TAG\")\n"
  printf "\n  -branch <branch>            : Coot branch (default = \"$COOT_BRANCH\")\n"
  printf "\n  -debug                      : Do debug build\n"
  printf "\n  -clean                      : Run make clean after building\n"
  printf "\n  -patch <file>               : Coot patch file\n"
  printf "\n  -no_chapi                   : Do not build Coot headless API\n"

  printf "\n Build-phase selectors (mutually exclusive; with none of these the whole build runs):\n"
  printf "\n  -download-only              : only download the toolchain + dependency sources (NOT Coot), then stop\n"
  printf "\n  -toolchain-only             : only build the bootstrap toolchain (Python, CMake, Ninja, Rust), then stop\n"
  printf "\n  -deps-only                  : only build the dependency stack, then stop\n"
  printf "\n  -coot-stage-only            : only download+build Coot (+chapi) and package, then stop\n"
  printf "\n                                (for caching CI: run -download-only, -toolchain-only, -deps-only in the\n"
  printf "\n                                 same dir to populate+cache the prefix, then -coot-stage-only after restore)\n"

  printf "\n Influential environment variables (override the defaults when set):\n"
  printf "\n  COOT_GIT             : Coot git repository URL (default = https://github.com/pemsley/coot)\n"
  printf "\n  CC / CXX / FC / F77  : C / C++ / Fortran compilers (default = newest gcc/g++/gfortran in the supported range)\n"

  printf "\n Tested on:\n"
  printf "   AlmaLinux 8.10 and 9.5 (todo: test again)\n"
  printf "   Arch Linux (20260402)\n"
  printf "   Debian 13\n"
  printf "   Fedora Linux 43 and 44\n"
  printf "   openSUSE Leap 15.6\n"
  printf "   Rocky Linux 9.3\n"
  printf "   Ubuntu 24.04 and 26.04\n"
}

## -------------------------------------------------------------------------------
## Command-line arguments
## -------------------------------------------------------------------------------
iverb=0
nthreads=`nproc --all`
do_minimaltar=1   # default: build a minimal tarball; -fulltar flips this to 0
do_distributable=0
do_noninteractive=0
do_os=1   # default: install OS packages via the system package manager (-no-use-os-package-manager to skip)
tag=""
branch=""
COOT_TAG="main"
COOT_BRANCH=""
patch_file=""
no_chapi=0
btype="opt"
do_clean=0
stage=all   # which build phase to run; a -*-only flag narrows this to a single phase
while [ $# -gt 0 ]
do
   case $1 in
    -h|-help|--help)usage;exit 0;;
    -v)iverb=`expr $iverb + 1`;;
    -nthreads)nthreads=$2;shift;;
    -fulltar)do_minimaltar=0;;
    -distributable)do_distributable=1;;
    -clean) do_clean=1;;
    -use-os-package-manager) do_os=1;;
    -no-use-os-package-manager) do_os=0;;
    -noninteractive) do_noninteractive=1;;
    -tag) tag=$2;outtag=${tag#Release-};shift;;
    -branch) branch=$2;outtag=$branch;shift;;
    -debug) btype="debug";;
    -no_chapi) no_chapi=1;;
    # Build-phase selectors: each runs exactly one phase and they do not chain.
    -download-only)   [ "$stage" = all ] || error "only one -*-only phase flag allowed"; stage=download;;
    -toolchain-only)  [ "$stage" = all ] || error "only one -*-only phase flag allowed"; stage=toolchain;;
    -deps-only)       [ "$stage" = all ] || error "only one -*-only phase flag allowed"; stage=deps;;
    -coot-stage-only) [ "$stage" = all ] || error "only one -*-only phase flag allowed"; stage=coot;;
    -patch)
      [ ! -f "$2" ] && error "file for -patch command not found = \"$2\""
      case "$2" in
        /*) patch_file=$2;;
        *) patch_file=`pwd`/$2;;
      esac
      shift
      ;;
    *) error "unknown argument = \"$1\"";;
  esac
  shift
done

## -------------------------------------------------------------------------------
## OS-specific packages etc
## -------------------------------------------------------------------------------
if [ $do_os -eq 1 ]; then
  [ "X$os" = "X" ] && error "unable to figure out OS version and/or Linux distro)!"

  case `id -nu` in
    root) sudo="";;
    *) sudo=sudo;;
  esac

  if [ $do_noninteractive -eq 0 ]; then
    printf "\n\n"
    printf " ################################################################################################\n"
    printf " #### WARNING: we will now install some OS packages as root (or sudo user) - continue ... y/[N] ? "
    read __answer
    [ "X$__answer" != "Xy" ] && printf " ... exiting ...\n" && exit 0
    printf "\n\n"
  else
    printf "\n\n"
    printf "#### Attempting to install OS packages as root..."
    printf "\n\n"
    export DEBIAN_FRONTEND=noninteractive
  fi

  case `echo "$os" | tr '[A-Z]' '[a-z]'` in
    opensuse*)
      # extract the major version (e.g. 15 from "openSUSE Leap-15.6")
      _suse_major=$(echo "$os" | sed 's/.*[^0-9]\([0-9][0-9]*\)\.[0-9][0-9]*.*/\1/')
      # probably not all needed:
      $sudo zypper install -y --force-resolution --allow-downgrade -t pattern devel_basis || error
      # probably not all needed:
      $sudo zypper install -y \
             wget \
             git \
             vim \
             gzip bzip2 \
             hostname \
             autoconf \
             automake \
             cmake \
             libtool \
             swig \
             libdrm-devel \
             libXrandr-devel \
             libXi-devel \
             libXcursor-devel \
             libXinerama-devel \
             libXdamage-devel \
             libXtst-devel \
             dbus-1-devel \
             libxcb-devel \
             xcb-util-devel \
             xcb-util-renderutil-devel \
             libX11-devel \
             libXrender-devel \
             libXext-devel \
             libxkbcommon-devel \
             Mesa-libGL-devel \
             Mesa-libEGL-devel \
             Mesa-libGLESv2-devel \
             gmp-devel \
             libglfw-devel \
             gperftools-devel \
             xmlto \
             docbook_4 \
             docbook-xsl-stylesheets \
             bc \
             gperf \
             file \
             gettext-tools \
             glibc-locale \
             openal-soft-devel \
             libseccomp-devel \
             doxygen \
             || error
      if [ "$_suse_major" -lt 16 ] 2>/dev/null; then
        # Leap < 16 ships an older system GCC; install GCC 13 explicitly.
        $sudo zypper install -y --force-resolution --allow-downgrade \
               gcc13 gcc13-fortran gcc13-c++ || error
        # openSUSE, ever so helpful, ships a stale fixincludes bits/floatn.h that
        # shadows glibc's good one and breaks <tgmath.h>. Nuke it so gcc sees the real header.
        $sudo rm -f "$(gcc-13 -print-file-name=include-fixed)/bits/floatn.h"
      else
        # Leap >= 16: system default GCC is recent enough.
        # devel_basis only recommends gcc-c++ and doesn't include gfortran — pull them in explicitly.
        $sudo zypper install -y --force-resolution --allow-downgrade \
               gcc gcc-c++ gcc-fortran || error
      fi
      ;;
    rocky*|alma*|centos*)
        #$sudo dnf update -y
        $sudo dnf install -y dnf-plugins-core
        $sudo dnf config-manager --set-enabled crb
        $sudo dnf install -y epel-release
        # This doesn't work. What does it do?
        # $sudo dnf config-manager --set-enabled powertools
        $sudo dnf update -y
        case `echo "$os" | tr '[A-Z]' '[a-z]'` in
          centos-10*|almalinux-10*) __toolsets="";;
          *) __toolsets="gcc-toolset-15 gcc-toolset-14";;
        esac
        $sudo yum -y install \
            gcc \
            wget \
            vim \
            gcc-c++ \
            gcc-gfortran \
            make \
            cmake \
            $__toolsets \
            gperf file \
            libX11-devel \
            libglvnd-devel \
            libxkbcommon-devel \
            libXrender-devel \
            libXext-devel \
            libXrandr-devel \
            libXi-devel \
            libXcursor-devel \
            libXdamage-devel \
            libXinerama-devel \
            libXtst-devel \
            libdrm-devel \
            tar \
            bison \
            bzip2 \
            autoconf \
            automake \
            libtool \
            perl-core \
            git \
            flex \
            gperftools-devel \
            dbus-devel \
            libxcb-devel \
            xcb-util-devel \
            gmp-devel \
            glfw-devel \
            bc \
            gettext \
            gperf \
            xmlto \
            pkgconf-pkg-config \
            xz \
            glibc-langpack-en \
            glibc-gconv-extra \
            openal-soft-devel \
            libseccomp-devel \
            doxygen \
            || error
      ;;
    fedora*)
        case `echo "$os" | tr '[A-Z]' '[a-z]'` in
          fedora-4[5-9]) printf "\n ############### WARNING - untested Fedora version !!!!\n\n";;
        esac
        $sudo dnf update -y
        $sudo dnf install -y dnf-plugins-core
        #$sudo dnf install -y epel-release
        $sudo dnf update -y
        case `echo "$os" | tr '[A-Z]' '[a-z]'` in
          fedora-4[2-9]) __toolsets="gcc15 gcc15-gfortran gcc15-c++";yum="dnf install --skip-unavailable -y";; # probably won't work
          *) __toolsets="gcc14 gcc14-gfortran gcc14-c++";yum="yum install -y";;
        esac
        $sudo $yum \
              gcc \
              wget \
              vim \
              hostname \
              gcc-c++ \
              gcc-gfortran \
              cmake \
              libX11-devel \
              libglvnd-devel \
              libxkbcommon-devel \
              libXrender-devel \
              libXext-devel \
              libXrandr-devel \
              libXi-devel \
              libXcursor-devel \
              tar \
              bison \
              libXdamage-devel \
              libXinerama-devel \
              libXtst-devel \
              libdrm-devel \
              bzip2 \
              autoconf \
              automake \
              libtool \
              perl-core \
              git \
              flex \
              gperf \
              file \
              gperftools-devel \
              $__toolsets \
              dbus-devel \
              libxcb-devel \
              xcb-util-devel \
              gmp-devel \
              glfw-devel \
              bc \
              gettext \
              make \
              xmlto \
              pkgconf-pkg-config \
              glibc-gconv-extra \
              openal-soft-devel \
              libseccomp-devel \
              doxygen
      ;;
    debian*|ubuntu*)
        $sudo apt-get update || error
        $sudo apt-get -y install \
          git wget build-essential gfortran gettext pkg-config bison flex make automake cmake gperf file vim xmlto libtool-bin \
          libdbus-1-dev \
          libxcb-glx0-dev \
          libegl1-mesa-dev \
          libxrender-dev libxcb-render0-dev libxcb-render-util0-dev libxext-dev libxrandr-dev libxi-dev libxcursor-dev \
          libxdamage-dev libxinerama-dev libxtst-dev \
          libxkbcommon-x11-dev libxcb-shm0-dev libxcb-util-dev libxcb1-dev libx11-dev libxcb-dri3-dev libx11-xcb-dev \
          libgmp-dev libdrm-dev \
          libglfw3-dev \
          xz-utils \
          libopenal-dev \
          libseccomp-dev \
          doxygen \
          bc || error
      ;;
    arch*)
      $sudo pacman -Syu --needed --noconfirm \
            base-devel git wget gcc-fortran gperf vim xmlto docbook-xml docbook-xsl cmake \
            dbus \
            xz bzip2 \
            libxcb \
            mesa \
            libxrender xcb-util-renderutil libxext libxrandr libxi libxcursor \
            libxdamage libxinerama libxtst \
            libxkbcommon xcb-util libx11 \
            gmp libdrm \
            glfw \
            inetutils bc openal libseccomp doxygen || error
      ;;
    *) error "unsupported OS!";;
  esac
fi

[ $iverb -ge 1 ] && set -x

## -------------------------------------------------------------------------------
## everything related to Coot itself
## -------------------------------------------------------------------------------
do_cleans=""
# potentially override:
[ "X$COOT_GIT" = "X" ] && COOT_GIT="https://github.com/pemsley/coot"
if [ "X$branch" != "X" ]; then
  COOT_TAG=""
  COOT_BRANCH="$branch"
  COOT_DIR=`echo coot-${COOT_BRANCH} | sed "s/ /_/g" | sed "s%/%-%g"`
else
  if [ "X$tag" != "X" ]; then
    COOT_TAG="$tag"
  fi
  COOT_BRANCH=""
  if [ "X$COOT_TAG" != "X" ]; then
    COOT_DIR=`echo coot-${COOT_TAG} | sed "s/ /_/g" | sed "s%/%-%g"`
  else
    COOT_DIR=`echo coot | sed "s/ /_/g" | sed "s%/%-%g"`
  fi
fi

export COOT_DIR

# Fixed dependency build list (NOT user-overridable). Order matters - and some packages
# must be built more than once (see the numbered build_<name> variants).
BUILD_DEPENDENCIES="
    util_linux
    icu
    libxml2
    elfutils
    libdwarf
    libbackward
    pcre2
    glib
    gobject_introspection
    libunistring
    gc
    glm
    guile
    swig
    eigen
    libepoxy
    boost
    glib
    graphene
    libpng
    harfbuzz
    freetype
    fontconfig
    libogg
    libvorbis
    libjpeg
    pixman
    cairo
    harfbuzz
    fribidi
    pango
    smi
    gdk_pixbuf
    librsvg
    tiff
    curl
    poppler
    highway
    lcms2
    libjxl
    libcap
    bubblewrap
    glycin
    gdk_pixbuf
    at_spi2_core
    wayland
    gtk
    adwaita_icon_theme
    glycin
    pygobject
    fftw
    maeparser
    coordgen
    rdkit
    mmdb2
    openblas
    gsl
    gemmi
    libccp4
    libssm
    libclipper"
# -------------------------------------------------------------------------------------

# versions of all external packages/dependencies:
CMAKE_VER=4.3.1
NINJA_VER=1.13.2

PYTHON_VER_MAJOR=3
PYTHON_VER_MINOR=14
PYTHON_VER_PATCH=5

BOOST_VER=1.91.0
# Boost's CMake archive has a release revision: boost-<ver>-<rev>-cmake.*
BOOST_CMAKE_REV=1
PYGOBJECT_VER=3.56.3
RDKIT_VER=2026_03_3
NUMPY_VER=2.4.3

PYTHON_VER="${PYTHON_VER_MAJOR}.${PYTHON_VER_MINOR}.${PYTHON_VER_PATCH}"

LIBJPEG_VER=3.1.4.1
GLIB_VER=2.88.1
GOBJECT_INTROSPECTION_VER_MM=1.86
GOBJECT_INTROSPECTION_VER=${GOBJECT_INTROSPECTION_VER_MM}.0
GUILE_VER=3.0.11
SWIG_VER=4.4.1
LIBEPOXY_VER=1.5.10
GRAPHENE_VER=1.10.8
HARFBUZZ_VER=14.2.1
FREETYPE_VER=2.14.3
LIBPNG_VER=1.6.58
FONTCONFIG_VER=2.18.1
FONTS_INTER_VER=4.1
FONTS_JETBRAINS_VER=2.304
FONTS_DEJAVU_VER=2.37
PIXMAN_VER=0.46.4
LIBTIFF_VER=4.7.1
POPPLER_VER=26.05.0
CURL_VER=8.20.0
CAIRO_VER=1.18.4
FRIBIDI_VER=1.0.16
PANGO_VER_MM=1.57
PANGO_VER=${PANGO_VER_MM}.1
SMI_VER=2.4
LIBRSVG_VER_MM=2.62
LIBRSVG_VER=${LIBRSVG_VER_MM}.3
HIGHWAY_VER=1.4.0
LCMS2_VER=2.19.1
LIBJXL_VER=0.11.2
LIBCAP_VER=2.78
BUBBLEWRAP_VER=0.11.2
GLYCIN_VER=2.1.1
GDK_PIXBUF_VER_MM=2.44
GDK_PIXBUF_VER=${GDK_PIXBUF_VER_MM}.6
AT_SPI2_CORE_VER=2.60.4
GTK_VER_Major=4
GTK_VER_Minor=22
GTK_VER_Patch=4
GTK_VER=${GTK_VER_Major}.${GTK_VER_Minor}.${GTK_VER_Patch}
ADWAITA_ICON_THEME_VER_MAJOR=50
ADWAITA_ICON_THEME_VER=${ADWAITA_ICON_THEME_VER_MAJOR}.0
MMDB_VER=2.0.22
OPENBLAS_VER=0.3.33
GSL_VER=2.8
GEMMI_VER=0.7.5
LIBCCP4_VER=8.0.0
LIBSSM_VER=1.4
LIBCLIPPER_VER_PRE=2.1
LIBCLIPPER_VER_PATCH=20201109
LIBCLIPPER_VER=${LIBCLIPPER_VER_PRE}.${LIBCLIPPER_VER_PATCH}
FFTW_VER=2.1.5
# LIBUNISTRING_VER=1.4
LIBUNISTRING_VER=1.2
GC_VER=8.2.12
GLM_VER=1.0.3
PCRE2_VER=10.47
LIBFFI_VER=3.5.2
ICU_VER=78.3
LIBXML2_VER=2.15.3
UTIL_LINUX_VER=2.42.1
BZIP2_VER=1.0.8
ZLIB_VER=1.3.2
ZSTD_VER=1.5.7
BROTLI_VER=1.2.0
XZ_VER=5.8.3
NCURSES_VER=6.6
READLINE_VER=8.3
OPENSSL_VER=3.6.3
WAYLAND_VER=1.25.0
WAYLANDPROTOCOLS_VER=1.49
EXPAT_VER=2.8.1
SQLITE_VER=3.53.2
# sqlite's tarball/URL use a zero-padded numeric form (3.53.2 -> 3530200)
SQLITE_SRCVER=$(printf '%d%02d%02d00' $(echo ${SQLITE_VER} | sed 's/\./ /g'))
MAEPARSER_VER=1.3.3
COORDGEN_VER=3.0.2
EIGEN_VER=5.0.1
LIBOGG_VER=1.3.6
LIBVORBIS_VER=1.3.7
ELFUTILS_VER=0.195
LIBDWARF_VER=2.3.1
LIBBACKWARD_VER=1.6

# -------------------------------------------------------------------------------------
# As mentioned above, everything happens inside the current directory:
export PREFIX=`pwd`
export BUILD_DIR=${PREFIX}/build
export DEPS_DIR=${PREFIX}/deps
export COOT_DOWNLOAD_DIR=$PREFIX
export COOT_BUILD_DIR=$COOT_DOWNLOAD_DIR/$COOT_DIR
export CARGO_HOME=${PREFIX}/.cargo
# RUSTUP_HOME holds the actual toolchains (rustc, std, components); without this it
# defaults to $HOME/.rustup, i.e. outside $PREFIX. Keep all of Rust under $PREFIX.
export RUSTUP_HOME=${PREFIX}/.rustup

cat <<e

  host ................................. `hostname`
  date ................................. `date`
  directory ............................ `pwd`
  user ................................. `id -nu`
  os.................................... $os
  build type ........................... $btype
  distributable ........................ `[ $do_distributable -eq 1 ] && echo yes || echo no`
  tarball .............................. `[ $do_minimaltar -eq 1 ] && echo minimal || echo full`

  COOT_GIT ............................. $COOT_GIT
  COOT_TAG ............................. $COOT_TAG
  COOT_BRANCH .......................... $COOT_BRANCH

  PREFIX ............................... $PREFIX
  BUILD_DIR ............................ $BUILD_DIR
  DEPS_DIR ............................. $DEPS_DIR
  COOT_DOWNLOAD_DIR .................... $COOT_DOWNLOAD_DIR
  COOT_BUILD_DIR ....................... $COOT_BUILD_DIR
  CARGO_HOME ........................... $CARGO_HOME
  RUSTUP_HOME .......................... $RUSTUP_HOME

e

# -------------------------------------------------------------------------------------
# Figure out the best available GCC version (highest preferred).
# We need all three frontends (C, C++, Fortran) at the same version.
# If no version has all three, we fall back to the highest version that has at least
# C and C++.  setup_build_env later sets CC/CXX/FC from GCC_COMMAND_EXT uniformly.
GCC_VER_MIN=11      # oldest supported version
GCC_VER_MAX=16      # newest tested/preferred version
GCC_VER_CEILING=25  # scan up to this version; anything above GCC_VER_MAX is untested but allowed
__gcc_fallback_ver=""
for __gcc_ver in `seq $GCC_VER_CEILING -1 $GCC_VER_MIN`
do
  type g++-${__gcc_ver} >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    # C++ compiler found — the matching C compiler must also exist.
    type gcc-${__gcc_ver} >/dev/null 2>&1
    if [ $? -ne 0 ]; then
      error "C++ compiler (g++-${__gcc_ver}) found but the matching C compiler (gcc-${__gcc_ver}) is missing"
    fi
    type gfortran-${__gcc_ver} >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      export GCC_COMPILER_VERSION=${__gcc_ver}
      export GCC_COMMAND_EXT="-${__gcc_ver}"
      break
    else
      echo " WARNING: C and C++ compilers at version ${__gcc_ver} found, but Fortran compiler (gfortran-${__gcc_ver}) is missing!"
      if [ "X$__gcc_fallback_ver" = "X" ]; then
        __gcc_fallback_ver=${__gcc_ver}
      fi
    fi
  else
    type gcc-${__gcc_ver} >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      echo " WARNING: C compiler (gcc-${__gcc_ver}) found but C++ compiler (g++-${__gcc_ver}) is missing!"
    fi
  fi
  # Fallback: check whether the unversioned g++ happens to be this version.
  # grep -c " 13\." counts lines containing " 13." — the dot prevents matching e.g. " 130."
  if [ "X$GCC_COMPILER_VERSION" = "X" ]; then
    type g++ >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      if [ `g++ --version 2>&1 | head -n1 | grep -c " ${__gcc_ver}\."` -eq 1 ]; then
        export GCC_COMPILER_VERSION=${__gcc_ver}
        export GCC_COMMAND_EXT=""
        break
      fi
    fi
  fi
done
# If no version had the full triple, fall back to the highest version that has C and C++.
if [ "X$GCC_COMPILER_VERSION" = "X" ] && [ "X$__gcc_fallback_ver" != "X" ]; then
  export GCC_COMPILER_VERSION=${__gcc_fallback_ver}
  export GCC_COMMAND_EXT="-${__gcc_fallback_ver}"
fi
[ "X$GCC_COMPILER_VERSION" = "X" ] && error "no working gcc/g++ found in version range $GCC_VER_MIN–$GCC_VER_CEILING"
printf "\n ### Compiler version found/used = $GCC_COMPILER_VERSION\n\n"
if [ $GCC_COMPILER_VERSION -gt $GCC_VER_MAX ]; then
  printf "\n ### NOTE: compiler version $GCC_COMPILER_VERSION is newer than the tested maximum ($GCC_VER_MAX) — should work but is untested\n"
elif [ $GCC_COMPILER_VERSION -lt $GCC_VER_MIN ]; then
  printf "\n ### WARNING: compiler version $GCC_COMPILER_VERSION is below the minimum supported version $GCC_VER_MIN\n"
elif [ $GCC_COMPILER_VERSION -lt $GCC_VER_MAX ]; then
  printf "\n ### NOTE: compiler version $GCC_COMPILER_VERSION is below the preferred version $GCC_VER_MAX\n"
  type scl >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    printf "\n ### NOTE: you might be able to switch to a preferred compiler version, e.g., via\n\n"
    printf "    scl enable gcc-toolset-$GCC_VER_MAX bash\n\n"
  fi
fi

# -------------------------------------------------------------------------------------
# generic build functions:
build_with_meson () {
  __p=$1;shift
  __v=$1;shift
  echo "build_with_meson \"$__p\" \"$__v\" => \$DEPS_DIR/${__p}-${__v} \$BUILD_DIR/$__p" >> /tmp/`basename ${0%.sh}`.debug
  if [ ! -f $BUILD_DIR/$__p/.my_done${MY_DONE_EXT} ]; then
    printf "\n ### building $__p ($__v) with meson\n"
    mkdir -p $BUILD_DIR/$__p || error
    cd $BUILD_DIR/$__p || error
    # Clean the build dir before a fresh meson setup; on a 2nd-pass build this also
    # preserves the previous pass's logs (my_*.log -> my_*.log1, this pass -> my_*.log2).
    build_save_mylogs_and_rm
    [ "$btype" = "debug" ] && __meson_buildtype=debugoptimized || __meson_buildtype=release
    printf "  meson setup (see `mypwd`/my_meson_setup.log${MY_DONE_EXT}) ... "
    meson setup --prefix=$PREFIX --buildtype=${__meson_buildtype} $@ . $DEPS_DIR/${__p}-${__v} > my_meson_setup.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_meson_setup.log${MY_DONE_EXT}"
    echo "done"
    cd $BUILD_DIR/$__p || error
    printf "  meson compile (see `mypwd`/my_meson_compile.log${MY_DONE_EXT}) ... "
    meson compile > my_meson_compile.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_meson_compile.log${MY_DONE_EXT}"
    echo "done"
    printf "  meson install (see `mypwd`/my_meson_install.log${MY_DONE_EXT}) ... "
    meson install > my_meson_install.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_meson_install.log${MY_DONE_EXT}"
    echo "done"
    do_cleans="$do_cleans `pwd`"
    cd $BUILD_DIR || error
    touch $BUILD_DIR/$__p/.my_done${MY_DONE_EXT}
  fi
}
# Wipes the current build directory (rm -rf *) so every build starts from a clean
# slate, while making sure no build log is silently lost across repeat builds.
#
# A "repeat build" is when the same package is built more than once (MY_DONE_EXT is
# set on the 2nd+ pass) — e.g. glycin and gdk-pixbuf are each built twice. The prior
# pass left "my_*.log" files in this directory that the rm -rf would destroy, so we:
#   1. rename the previous pass's "my_X.log" -> "my_X.log1" (numeric suffix per pass),
#   2. stash all "my_*.logN" in a PID-named temp dir so they survive the wipe,
#   3. rm -rf * to clear the build artifacts,
#   4. restore the stashed logs into the now-empty directory.
# Net result: pass 1's logs become my_*.log1, pass 2's are my_*.log2, etc. — preserved,
# not overwritten. On a first build (MY_DONE_EXT empty) it simply does the rm -rf *.
#
# Must be called with the current directory set to the package's build dir
# ($BUILD_DIR/$__p), since it operates on "." (the cwd).
build_save_mylogs_and_rm () {
  # When MY_DONE_EXT is set this is a repeat build; preserve logs from previous attempts
  # before wiping the build directory, then restore them afterwards.
  if [ "X$MY_DONE_EXT" != "X" ]; then
    # Rename my_foo.log → my_foo.log1 so repeat-attempt logs don't overwrite the first
    for log_file in `ls my_*.log 2>/dev/null`
    do
      [ ! -f ${log_file}1 ] && mv $log_file ${log_file}1
    done
    # $$ is the shell PID; used to make a unique temp dir that survives the rm -rf * below
    mkdir -p $PREFIX/__$$.tmpdir >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      for build_attempt in `seq 1 $MY_DONE_EXT`
      do
        mv my_*.log${build_attempt} $PREFIX/__$$.tmpdir/. 2>/dev/null
      done
    fi
  fi
  rm -rf *
  # restore saved logs into the freshly-cleared directory
  if [ -d $PREFIX/__$$.tmpdir ]; then
    mv $PREFIX/__$$.tmpdir/my*.log* . 2>/dev/null
    rm -fr $PREFIX/__$$.tmpdir 2>/dev/null
  fi
}

build_with_autogen_and_configure () {
  build_with_configure -autogen $@
}

build_with_configure () {
  __do_autogen=0
  [ "X$1" = "X-autogen" ] && shift && __do_autogen=1
  __p=$1;shift
  __v=$1;shift
  echo "build_with_configure \"$__p\" \"$__v\" => \$DEPS_DIR/${__p}-${__v} \$BUILD_DIR/$__p" >> /tmp/`basename ${0%.sh}`.debug
  if [ ! -f $BUILD_DIR/$__p/.my_done${MY_DONE_EXT} ]; then
    printf "\n ### building $__p ($__v) with configure/make\n"
    mkdir -p $BUILD_DIR/$__p || error
    cd $BUILD_DIR/$__p || error
    # Clean the build dir before configure/make; on a 2nd-pass build this also
    # preserves the previous pass's logs (my_*.log -> my_*.log1, this pass -> my_*.log2).
    build_save_mylogs_and_rm
    if [ $__do_autogen -eq 1 ]; then
      printf "  autogen.sh (see `mypwd`/my_autogen.log${MY_DONE_EXT}) ... "
      $DEPS_DIR/${__p}-${__v}/autogen.sh --prefix=$PREFIX > my_autogen.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_autogen.log${MY_DONE_EXT}"
      echo "done"
    fi
    # Inject the optimization level explicitly: autoconf only adds its -g -O2 default when
    # CFLAGS is *unset*, but additional_build_env_setup exports CFLAGS=-I$PREFIX/include, so
    # without this every configure dep would compile at -O0. opt -> -O2; debug -> -O2 -g.
    [ "$btype" = "debug" ] && __cfg_opt="-O2 -g" || __cfg_opt="-O2"
    printf "  configure (see `mypwd`/my_configure.log${MY_DONE_EXT}) ... "
    CFLAGS="${CFLAGS} ${__cfg_opt}" CXXFLAGS="${CXXFLAGS} ${__cfg_opt}" \
      $DEPS_DIR/${__p}-${__v}/configure --prefix=$PREFIX $@ > my_configure.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_configure.log${MY_DONE_EXT}"
    echo "done"

    # Belt-and-braces: strip a leftover bare "-g" from the Makefile in opt builds, in case a
    # package's configure injected one of its own (our CFLAGS above carries the real flags).
    case $btype in
      debug) ;;
      *) [ -f Makefile ] && \
           sed -e "s/^[ ]*CFLAGS[ ]*=[ ]*-g/CFLAGS =/g" \
               -e "s/^[ ]*CXXFLAGS[ ]*=[ ]*-g/CXXFLAGS =/g" Makefile > .Makefile && mv .Makefile Makefile;;
    esac

    printf "  make (see `mypwd`/my_make.log${MY_DONE_EXT}) ... "
    make -j ${nthreads} > my_make.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_make.log${MY_DONE_EXT}"
    echo "done"
    printf "  make install (see `mypwd`/my_make_install.log${MY_DONE_EXT}) ... "
    make install > my_make_install.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_make_install.log${MY_DONE_EXT}"
    echo "done"
    do_cleans="$do_cleans `pwd`"
    cd $BUILD_DIR || error
    touch $BUILD_DIR/$__p/.my_done${MY_DONE_EXT}
  fi
}
build_with_cmake () {
  __p=$1;shift
  __v=$1;shift
  echo "build_with_cmake \"$__p\" \"$__v\" => \$DEPS_DIR/${__p}-${__v} \$BUILD_DIR/$__p" >> /tmp/`basename ${0%.sh}`.debug
  if [ ! -f $BUILD_DIR/$__p/.my_done${MY_DONE_EXT} ]; then
    printf "\n ### building $__p ($__v) with cmake\n"
    mkdir -p $BUILD_DIR/$__p || error
    cd $BUILD_DIR/$__p || error
    # Clean the build dir before a fresh cmake configure; on a 2nd-pass build this also
    # preserves the previous pass's logs (my_*.log -> my_*.log1, this pass -> my_*.log2).
    build_save_mylogs_and_rm
    [ "$btype" = "debug" ] && __cmake_buildtype=RelWithDebInfo || __cmake_buildtype=Release
    printf "  cmake (see `mypwd`/my_cmake.log${MY_DONE_EXT}) ... "
    cmake $DEPS_DIR/${__p}-${__v} \
          -DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_BUILD_TYPE=${__cmake_buildtype} $@ > my_cmake.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_cmake.log${MY_DONE_EXT}"
    echo "done"
    printf "  cmake --build (see `mypwd`/my_cmake_build.log${MY_DONE_EXT}) ... "
    cmake --build . -j ${nthreads} > my_cmake_build.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_cmake_build.log${MY_DONE_EXT}"
    echo "done"
    printf "  cmake --install (see `mypwd`/my_cmake_install.log${MY_DONE_EXT}) ... "
    cmake --install .  > my_cmake_install.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_cmake_install.log${MY_DONE_EXT}"
    echo "done"
    do_cleans="$do_cleans `pwd`"
    cd $BUILD_DIR || error
    touch $BUILD_DIR/$__p/.my_done${MY_DONE_EXT}
  fi
}

# -------------------------------------------------------------------------------------
# specific build functions

build_python () {
  build_with_configure python ${PYTHON_VER} --libdir=$PREFIX/lib --enable-optimizations --with-system-expat=true --with-lto=full \
  --without-static-libpython --enable-shared --with-openssl=$PREFIX
}

build_libjpeg () {
  build_with_cmake libjpeg-turbo ${LIBJPEG_VER} \
    -DCMAKE_INSTALL_LIBDIR=$PREFIX/lib \
    -DENABLE_STATIC=OFF \
    -DWITH_JAVA=OFF \
    -DWITH_TESTS=OFF
}

build_libunistring () {
  build_with_configure libunistring ${LIBUNISTRING_VER}
}

build_gc () {
  build_with_configure gc ${GC_VER} --enable-cplusplus --disable-static
}

build_glm () {
  build_with_cmake glm ${GLM_VER}
}

# bzip2 has no autotools/cmake — hand-rolled. Build only the shared library
# Ships libbz2 (for linking) and the bzip2/bunzip2/bzcat CLIs (for tar's .tar.bz2 path).
build_bzip2 () {
  if [ ! -f $BUILD_DIR/bzip2/.my_done${MY_DONE_EXT} ]; then
    printf "\n ### building bzip2 (${BZIP2_VER}) with make\n"
    rm -rf $BUILD_DIR/bzip2
    cp -a $DEPS_DIR/bzip2-${BZIP2_VER}/ $BUILD_DIR/bzip2 || error
    cd $BUILD_DIR/bzip2 || error

    printf "  make libbz2.so (see `mypwd`/my_make.log${MY_DONE_EXT}) ... "
    # Override the Makefile's hardcoded "-O2 -g" so the build honors $btype: opt drops -g,
    # debug keeps it. -fPIC + the BIGFILES define are mandatory for the shared lib; LDFLAGS
    # rides on CC because Makefile-libbz2_so links with $(CC).
    [ "$btype" = "debug" ] && __bz_opt="-O2 -g" || __bz_opt="-O2"
    make -f Makefile-libbz2_so CC="${CC} ${LDFLAGS}" \
         CFLAGS="${CFLAGS} -fpic -fPIC -Wall -Winline ${__bz_opt} -D_FILE_OFFSET_BITS=64" \
         > my_make.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_make.log${MY_DONE_EXT}"
    echo "done"

    # bzip2/bzip2recover CLIs (link statically against libbz2.a; LDFLAGS rides on CC).
    printf "  make bzip2 binary (see `mypwd`/my_make_bin.log${MY_DONE_EXT}) ... "
    make -f Makefile bzip2 bzip2recover CC="${CC} ${LDFLAGS}" \
         CFLAGS="${CFLAGS} -Wall -Winline ${__bz_opt} -D_FILE_OFFSET_BITS=64" \
         > my_make_bin.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_make_bin.log${MY_DONE_EXT}"
    echo "done"

    printf "  installing libbz2 (see `mypwd`/my_install.log${MY_DONE_EXT}) ... "
    {
      install -m755 libbz2.so.${BZIP2_VER} $PREFIX/lib/ || error
      install -m755 bzip2 $PREFIX/bin/ || error
      install -m755 bzip2recover $PREFIX/bin/ || error
      ln -sf bzip2 $PREFIX/bin/bunzip2
      ln -sf bzip2 $PREFIX/bin/bzcat
      ln -sf libbz2.so.${BZIP2_VER} $PREFIX/lib/libbz2.so
      ln -sf libbz2.so.${BZIP2_VER} $PREFIX/lib/libbz2.so.1
      # libbz2.so.1.0 is the soname (-Wl,-soname,libbz2.so.1.0); without it our own
      # consumers (Python _bz2) can't load the lib unless the host ships a system one.
      ln -sf libbz2.so.${BZIP2_VER} $PREFIX/lib/libbz2.so.1.0
      install -m644 bzlib.h $PREFIX/include/ || error

      # pkg-config file — upstream doesn't ship one; cmake's FindBZip2 probes it
      cat > $PREFIX/lib/pkgconfig/bzip2.pc <<EOF
prefix=$PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: bzip2
Description: A file compression library
Version: ${BZIP2_VER}
Libs: -L\${libdir} -lbz2
Cflags: -I\${includedir}
EOF
    } > my_install.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_install.log${MY_DONE_EXT}"
    echo "done"

    do_cleans="$do_cleans `pwd`"
    cd $BUILD_DIR || error
    touch $BUILD_DIR/bzip2/.my_done${MY_DONE_EXT}
  fi
}

build_zlib () {
  build_with_cmake zlib ${ZLIB_VER} \
    -DZLIB_BUILD_SHARED=ON -DZLIB_BUILD_STATIC=OFF
}

# zstd's CMakeLists.txt lives under build/cmake/ — hand-rolled.
build_zstd () {
  if [ ! -f $BUILD_DIR/zstd/.my_done${MY_DONE_EXT} ]; then
    printf "\n ### building zstd (${ZSTD_VER}) with cmake\n"
    mkdir -p $BUILD_DIR/zstd || error
    cd $BUILD_DIR/zstd || error
    build_save_mylogs_and_rm

    printf "  cmake (see `mypwd`/my_cmake.log${MY_DONE_EXT}) ... "
    [ "$btype" = "debug" ] && __cmake_buildtype=RelWithDebInfo || __cmake_buildtype=Release
    cmake -S $DEPS_DIR/zstd-${ZSTD_VER}/build/cmake -B . \
          -DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_BUILD_TYPE=${__cmake_buildtype} \
          -DZSTD_BUILD_SHARED=ON -DZSTD_BUILD_STATIC=OFF \
          -DZSTD_BUILD_PROGRAMS=ON -DZSTD_PROGRAMS_LINK_SHARED=ON -DZSTD_BUILD_TESTS=OFF \
          -DZSTD_BUILD_CONTRIB=OFF > my_cmake.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_cmake.log${MY_DONE_EXT}"
    echo "done"

    printf "  cmake --build (see `mypwd`/my_cmake_build.log${MY_DONE_EXT}) ... "
    cmake --build . -j ${nthreads} > my_cmake_build.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_cmake_build.log${MY_DONE_EXT}"
    echo "done"

    printf "  cmake --install (see `mypwd`/my_cmake_install.log${MY_DONE_EXT}) ... "
    cmake --install . > my_cmake_install.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_cmake_install.log${MY_DONE_EXT}"
    echo "done"

    do_cleans="$do_cleans `pwd`"
    cd $BUILD_DIR || error
    touch $BUILD_DIR/zstd/.my_done${MY_DONE_EXT}
  fi
}

build_brotli () {
  build_with_cmake brotli ${BROTLI_VER} \
    -DBUILD_SHARED_LIBS=ON -DBROTLI_BUILD_TOOLS=ON
}

build_xz () {
  build_with_configure xz ${XZ_VER} --disable-static --disable-nls --disable-doc \
    --disable-scripts --disable-lzmainfo
}

build_pcre2 () {
  build_with_configure pcre2 ${PCRE2_VER} --enable-unicode --enable-jit --enable-pcre2-16 --enable-pcre2-32 --enable-pcre2grep-libz --enable-pcre2grep-libbz2 --disable-static
}

build_libffi () {
  build_with_configure libffi ${LIBFFI_VER} --disable-static --disable-multi-os-directory
}

# ncurses (widec). Two non-obvious flags, both needed for Python's _curses to import:
#  - NO --with-termlib: keep terminfo + the curses symbols (e.g. _nc_acs_map) in one
#    libncursesw. --with-termlib splits them into libtinfow, where _curses can't reach them.
#  - NO --enable-overwrite: install headers under include/ncursesw/ so CPython's
#    `#include <ncursesw/curses.h>` resolves to OURS. With overwrite they land in include/
#    (no ncursesw/ subdir), and on a host with system ncurses-devel present (e.g. openSUSE's
#    devel_basis pulls 6.1) CPython falls back to that older header -> undefined _nc_acs_map.
# readline probes the non-wide termcap names, hence the libtinfo/libncurses symlinks below.
build_ncurses () {
  if [ ! -f $BUILD_DIR/ncurses/.my_done${MY_DONE_EXT} ]; then
    printf "\n ### building ncurses (${NCURSES_VER}) with configure/make\n"
    mkdir -p $BUILD_DIR/ncurses || error
    cd $BUILD_DIR/ncurses || error
    build_save_mylogs_and_rm

    # ncurses adds no -O of its own when CFLAGS is set, so inject it (see build_with_configure).
    [ "$btype" = "debug" ] && { __nc_debug="--with-debug"; __opt="-O2 -g"; } || { __nc_debug="--without-debug"; __opt="-O2"; }
    printf "  configure (see `mypwd`/my_configure.log${MY_DONE_EXT}) ... "
    CFLAGS="${CFLAGS} ${__opt}" CXXFLAGS="${CXXFLAGS} ${__opt}" \
    $DEPS_DIR/ncurses-${NCURSES_VER}/configure --prefix=$PREFIX \
      --with-shared --without-normal ${__nc_debug} --without-ada --without-cxx-binding \
      --enable-widec --enable-pc-files --with-versioned-syms \
      --with-pkg-config-libdir=$PREFIX/lib/pkgconfig > my_configure.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_configure.log${MY_DONE_EXT}"
    echo "done"

    printf "  make (see `mypwd`/my_make.log${MY_DONE_EXT}) ... "
    make -j ${nthreads} > my_make.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_make.log${MY_DONE_EXT}"
    echo "done"
    printf "  make install (see `mypwd`/my_make_install.log${MY_DONE_EXT}) ... "
    make install > my_make_install.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_make_install.log${MY_DONE_EXT}"
    echo "done"

    # Non-wide aliases so -ltinfo / -lncurses / -lcurses resolve to our one widec lib.
    ln -sf libncursesw.so $PREFIX/lib/libncurses.so
    ln -sf libncursesw.so $PREFIX/lib/libcurses.so
    ln -sf libncursesw.so $PREFIX/lib/libtinfo.so
    # Same for form/menu/panel — without these, code that probes -lform / -lmenu / -lpanel
    # (e.g. CMake's bootstrap) falls back to the system libs, which on older distros
    # reference _nc_stdscr (ncurses <=6.2 internal, renamed to _nc_stdscr_of in >=6.3).
    ln -sf libformw.so  $PREFIX/lib/libform.so
    ln -sf libmenuw.so  $PREFIX/lib/libmenu.so
    ln -sf libpanelw.so $PREFIX/lib/libpanel.so
    ln -sf ncursesw.pc    $PREFIX/lib/pkgconfig/ncurses.pc
    ln -sf ncursesw.pc    $PREFIX/lib/pkgconfig/tinfo.pc
    # Non-wide header symlinks — CMake's bootstrap and other find_path users probe
    # for curses.h directly (not ncursesw/curses.h), so they must be resolvable
    # from $PREFIX/include without the ncursesw/ subdirectory.
    for __h in curses.h form.h menu.h panel.h ncurses.h term.h; do
      ln -sf ncursesw/$__h $PREFIX/include/$__h
    done

    do_cleans="$do_cleans `pwd`"
    cd $BUILD_DIR || error
    touch $BUILD_DIR/ncurses/.my_done${MY_DONE_EXT}
  fi
}

# Static-only (-fPIC so it embeds into Python's/guile's shared modules). A shared libreadline.so.8
# would shadow the host bash's via LD_LIBRARY_PATH; where that bash links a symbol-versioned system
# readline (openSUSE Leap 16) it'd warn "no version information available" and break g-ir-scanner.
build_readline () {
  CFLAGS="$CFLAGS -fPIC" build_with_configure readline ${READLINE_VER} --disable-shared --enable-static
  # Static readline references termcap globals (UP/BC/PC) it doesn't define; the shared lib carried
  # a NEEDED on ncurses, a .a can't. Promote the dep from Requires.private to public Libs so plain
  # pkg-config consumers (CPython's readline module) link -ltinfo and resolve UP at load.
  # grep: skip if already patched (idempotent on reruns; -- so -ltinfo isn't read as a flag).
  # sed: on the "Libs:" line, append " -ltinfo" right after the existing -lreadline.
  # if-block (not an && chain): when already patched the chain's last test would be the
  # function's nonzero return value, so `build_readline || error` aborted every rerun.
  __rlpc=$PREFIX/lib/pkgconfig/readline.pc
  if [ -f $__rlpc ] && ! grep -q -- "-ltinfo" $__rlpc; then
    sed -i "s/^\(Libs:.*-lreadline\)/\1 -ltinfo/" $__rlpc
  fi
}

# OpenSSL (Configure is perl, so hand-rolled). Built in the toolchain phase before Python
# (its ssl/hashlib + pip's HTTPS need it); curl links it later. install_sw skips the docs.
build_openssl () {
  if [ ! -f $BUILD_DIR/openssl/.my_done${MY_DONE_EXT} ]; then
    printf "\n ### building openssl (${OPENSSL_VER}) with Configure/make\n"
    rm -rf $BUILD_DIR/openssl
    cp -a $DEPS_DIR/openssl-${OPENSSL_VER}/ $BUILD_DIR/openssl || error
    cd $BUILD_DIR/openssl || error

    # --debug/--release set assertions; the -O flag (config arg) is needed because a set
    # CFLAGS suppresses openssl's own -O3 (verified: no -O in CNF_CFLAGS).
    [ "$btype" = "debug" ] && { __ssl_btype="--debug"; __opt="-O2 -g"; } || { __ssl_btype="--release"; __opt="-O2"; }
    printf "  config (see `mypwd`/my_configure.log${MY_DONE_EXT}) ... "
    ./config --prefix=$PREFIX --openssldir=$PREFIX/ssl --libdir=lib ${__ssl_btype} ${__opt} \
             shared no-tests enable-brotli enable-zlib enable-zstd > my_configure.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_configure.log${MY_DONE_EXT}"
    echo "done"

    printf "  make (see `mypwd`/my_make.log${MY_DONE_EXT}) ... "
    make -j ${nthreads} > my_make.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_make.log${MY_DONE_EXT}"
    echo "done"
    printf "  make install_sw (see `mypwd`/my_make_install.log${MY_DONE_EXT}) ... "
    make install_sw > my_make_install.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_make_install.log${MY_DONE_EXT}"
    echo "done"

    do_cleans="$do_cleans `pwd`"
    cd $BUILD_DIR || error
    touch $BUILD_DIR/openssl/.my_done${MY_DONE_EXT}
  fi
}

build_expat () {
  build_with_configure expat ${EXPAT_VER} --disable-static --without-examples --without-tests --without-docbook
}

build_sqlite () {
  build_with_configure sqlite ${SQLITE_VER} --disable-static --enable-readline --all
}

# Source dir is util-linux-*, so pass that (hyphen) name to the configure helper.
build_util_linux () {
  build_with_configure util-linux ${UTIL_LINUX_VER} \
    --disable-all-programs --enable-libuuid --enable-libblkid --enable-libmount \
    --disable-static --disable-nls --disable-bash-completion \
    --without-econf
}

# Hand-rolled: ICU's configure lives under source/, so build_with_configure can't drive it.
build_icu () {
  if [ ! -f $BUILD_DIR/icu/.my_done${MY_DONE_EXT} ]; then
    printf "\n ### building icu (${ICU_VER}) with configure/make\n"
    rm -rf $BUILD_DIR/icu
    cp -a $DEPS_DIR/icu-${ICU_VER}/ $BUILD_DIR/icu || error
    cd $BUILD_DIR/icu/source || error

    # ICU adds no -O when CFLAGS is set, so inject it (see build_with_configure). The
    # --enable-debug/--enable-release pair stays for ICU's internal assertion settings.
    [ "$btype" = "debug" ] && { __icu_btype="--enable-debug --disable-release"; __opt="-O2 -g"; } || { __icu_btype="--disable-debug --enable-release"; __opt="-O2"; }
    printf "  configure (see `mypwd`/my_configure.log${MY_DONE_EXT}) ... "
    CFLAGS="${CFLAGS} ${__opt}" CXXFLAGS="${CXXFLAGS} ${__opt}" \
    ./configure --prefix=$PREFIX \
                --enable-shared --disable-static ${__icu_btype} \
                --disable-samples --disable-tests > my_configure.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_configure.log${MY_DONE_EXT}"
    echo "done"

    printf "  make (see `mypwd`/my_make.log${MY_DONE_EXT}) ... "
    make -j ${nthreads} > my_make.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_make.log${MY_DONE_EXT}"
    echo "done"

    printf "  make install (see `mypwd`/my_make_install.log${MY_DONE_EXT}) ... "
    make install > my_make_install.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_make_install.log${MY_DONE_EXT}"
    echo "done"
    do_cleans="$do_cleans `pwd`"

    cd $BUILD_DIR || error
    touch $BUILD_DIR/icu/.my_done${MY_DONE_EXT}
  fi
}
# Built with ICU (ours, built right before); Python bindings + compression not needed.
# Provides xmllint for shared-mime-info. 2.15.x dropped autotools — meson only.
build_libxml2 () {
  build_with_meson libxml2 ${LIBXML2_VER} -Dicu=enabled -Dlegacy=enabled
}

build_wayland () {
  build_with_meson wayland ${WAYLAND_VER} -Dtests=false -Ddocumentation=false -Ddtd_validation=false
}
build_waylandprotocols () {
  build_with_meson wayland-protocols ${WAYLANDPROTOCOLS_VER}
}

build_libdwarf () {
  build_with_meson libdwarf ${LIBDWARF_VER}
}

build_libbackward () {
  build_with_cmake libbackward ${LIBBACKWARD_VER} -DCMAKE_POLICY_VERSION_MINIMUM=3.5
}

build_elfutils () {
  build_with_configure elfutils ${ELFUTILS_VER} --disable-debuginfod
}


# First pass without introspection: glib's own .gir files need gobject-introspection,
# which needs glib.  Second pass (after gobject-introspection) enables .gir generation.
build_glib () {
  build_with_meson glib ${GLIB_VER} -Dintrospection=disabled -Dtests=false -Dglib_debug=disabled
}
build_glib2 () {
  build_with_meson glib ${GLIB_VER} -Dintrospection=enabled -Dtests=false -Dglib_debug=disabled
}

build_gobject_introspection () {
  build_with_meson gobject_introspection ${GOBJECT_INTROSPECTION_VER} -Dtests=false
  if [ -d $PREFIX/share/gir-1.0 ]; then
    for __f in GObject-2.0.gir GLib-2.0.gir Gio-2.0.gir GModule-2.0.gir
    do
      if [ -f $BUILD_DIR/gobject_introspection/gir/$__f ] && [ ! -f $PREFIX/share/gir-1.0/$__f ]; then
        cp -p $BUILD_DIR/gobject_introspection/gir/$__f $PREFIX/share/gir-1.0/. || error
      fi
    done
  fi
}

build_guile () {
  build_with_configure guile ${GUILE_VER} --enable-shared --disable-static --disable-error-on-warning --enable-mini-gmp \
    --with-libreadline-prefix=$PREFIX
}

build_swig () {
  build_with_configure swig ${SWIG_VER}
}

# Build all of boost (full header tree for RDKit/poppler header-only use). Python is
# opt-in (BOOST_ENABLE_PYTHON); layout=system + our python3 -> libboost_python314.so.
build_boost () {
  build_with_cmake boost ${BOOST_VER} \
    -DBUILD_SHARED_LIBS=ON -DBOOST_INSTALL_LAYOUT=system -DBOOST_ENABLE_CMAKE=ON \
    -DBOOST_ENABLE_PYTHON=ON -DPython_EXECUTABLE=$PREFIX/bin/python3
}

build_libepoxy () {
  build_with_meson libepoxy ${LIBEPOXY_VER} -Dtests=false
}

# Harfbuzz auto-detects freetype, cairo, fontconfig, and glib (all feature=auto).
# Pass 1 lacks freetype/cairo; pass 2 finds them and enables those backends.
build_harfbuzz () {
  build_with_meson harfbuzz ${HARFBUZZ_VER} -Dtests=disabled -Dcpp_std=c++17
}
build_harfbuzz2 () {
  build_with_meson harfbuzz ${HARFBUZZ_VER} -Dtests=disabled -Dcpp_std=c++17
}

build_graphene () {
  build_with_meson graphene ${GRAPHENE_VER} -Dgtk_doc=false -Dtests=false -Dinstalled_tests=false
}

build_libpng () {
  build_with_cmake libpng ${LIBPNG_VER} \
    -DPNG_SHARED=ON -DPNG_STATIC=OFF -DPNG_TESTS=OFF -DPNG_TOOLS=OFF
}

build_freetype () {
  build_with_cmake freetype ${FREETYPE_VER} -DBUILD_SHARED_LIBS=true -DFT_ENABLE_ERROR_STRINGS=ON
}

build_fontconfig () {
  build_with_meson fontconfig ${FONTCONFIG_VER} -Ddoc=disabled
}

extract_fonts () {
  ( mkdir -p $PREFIX/share/fonts/truetype/inter && \
      cd $PREFIX/share/fonts/truetype/inter && \
      tar -xf $DEPS_DIR/fonts/Inter-${FONTS_INTER_VER}.tar.gz )
  ( mkdir -p $PREFIX/share/fonts/truetype/jetbrains-mono && \
      cd $PREFIX/share/fonts/truetype/jetbrains-mono && \
      tar -xf $DEPS_DIR/fonts/JetBrainsMono-${FONTS_JETBRAINS_VER}.tar.gz )
  ( mkdir -p $PREFIX/share/fonts/truetype/dejavu && \
      cd $PREFIX/share/fonts/truetype/dejavu && \
      tar -xf $DEPS_DIR/fonts/dejavu-fonts-ttf-${FONTS_DEJAVU_VER}.tar.bz2 )
  ( mkdir -p $PREFIX/share/fonts/truetype/dejavu && \
      cd $PREFIX/share/fonts/truetype/dejavu && \
      tar -xf $DEPS_DIR/fonts/dejavu-lgc-fonts-ttf-${FONTS_DEJAVU_VER}.tar.bz2 )
  ( mkdir -p $PREFIX/share/fonts/truetype && \
      cd $PREFIX/share/fonts/truetype && \
      tar -xf $DEPS_DIR/fonts/Noto.tar.gz )
}

build_pixman () {
  build_with_meson pixman ${PIXMAN_VER}
}

build_poppler () {
  build_with_cmake poppler ${POPPLER_VER} -DENABLE_NSS3=OFF \
  -DENABLE_GPGME=OFF -DBUILD_GTK_TESTS=OFF -DBUILD_QT5_TESTS=OFF \
  -DBUILD_QT6_TESTS=OFF -DBUILD_CPP_TESTS=OFF -DBUILD_MANUAL_TESTS=OFF \
  -DENABLE_BOOST=ON -DENABLE_QT5=OFF -DENABLE_QT6=OFF \
  -DENABLE_LIBOPENJPEG=none -DENABLE_LCMS=OFF -DENABLE_LIBCURL=ON -DENABLE_DCTDECODER=libjpeg
}

build_curl () {
    build_with_cmake curl ${CURL_VER} \
      -DCURL_USE_OPENSSL=ON \
      -DCURL_DISABLE_LDAP=ON \
      -DCURL_DISABLE_LDAPS=ON \
      -DCURL_USE_LIBSSH2=OFF \
      -DCURL_USE_LIBPSL=OFF \
      -DBUILD_TESTING=OFF \
      -DBUILD_LIBCURL_DOCS=OFF \
      -DBUILD_MISC_DOCS=OFF \
      -DENABLE_CURL_MANUAL=OFF \
      -DPICKY_COMPILER=OFF
}

build_tiff() {
  if [ ! -f $BUILD_DIR/libtiff/.my_done${MY_DONE_EXT} ]; then
    printf "\n ### building libtiff (${LIBTIFF_VER}) with autogen.sh/configure/make\n"
    rm -rf $BUILD_DIR/libtiff
    cp -a $DEPS_DIR/libtiff-v${LIBTIFF_VER}/ $BUILD_DIR/libtiff || error
    cd $BUILD_DIR/libtiff || error

    # adjust autogen.sh (avoid trying to fetch some updated configu.guess etc)
    awk '/Get latest config.guess/{ido=-1}{if(ido>=0)print}/done/{ido++}' autogen.sh > autogen.sh1 && mv autogen.sh1 autogen.sh && chmod +x autogen.sh
    printf "  running autogen (see `mypwd`/my_autogen.log${MY_DONE_EXT}) ... "
    ./autogen.sh --prefix=$PREFIX > my_autogen.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_autogen.log${MY_DONE_EXT}"
    echo "done"

    # Explicit opt: a set CFLAGS suppresses autoconf's -O2 default (see build_with_configure).
    [ "$btype" = "debug" ] && __opt="-O2 -g" || __opt="-O2"
    printf "  running configure (see `mypwd`/my_configure.log${MY_DONE_EXT}) ... "
    CFLAGS="${CFLAGS} ${__opt}" CXXFLAGS="${CXXFLAGS} ${__opt}" \
    ./configure --prefix=$PREFIX \
                --enable-cxx \
                --with-jpeg-lib-dir=$PREFIX/lib \
                --disable-lerc \
                --with-jpeg-include-dir=$PREFIX/include > my_configure.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_configure.log${MY_DONE_EXT}"
    echo "done"

    printf "  running make (see `mypwd`/my_make.log${MY_DONE_EXT}) ... "
    make -j ${nthreads} > my_make.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_make.log${MY_DONE_EXT}"
    echo "done"

    printf "  running install (see `mypwd`/my_make_install.log${MY_DONE_EXT}) ... "
    make install > my_make_install.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_make_install.log${MY_DONE_EXT}"
    echo "done"
    do_cleans="$do_cleans `pwd`"

    cd $BUILD_DIR || error
    touch $BUILD_DIR/libtiff/.my_done${MY_DONE_EXT}
  fi
}

# Cairo's features are all auto-detected and every dependency is already built
# before this point — a single pass is sufficient, no circular bootstrap needed.
build_cairo () {
  build_with_meson cairo ${CAIRO_VER} --wrap-mode=nodownload -Dtests=disabled -Dxlib-xcb=enabled -Dlzo=disabled
}

build_fribidi () {
  build_with_meson fribidi ${FRIBIDI_VER} -Ddocs=false -Dtests=false -Dbin=false
}

build_pango () {
  build_with_meson pango ${PANGO_VER} -Dintrospection=enabled -Dbuild-testsuite=false -Dbuild-examples=false -Dlibthai=disabled
}

build_smi () {
  build_with_meson shared-mime-info ${SMI_VER} -Dbuild-tests=false
}

# librsvg dropped autotools (autogen.sh/configure) for a Meson build in the 2.59+ series.
build_librsvg () {
  build_with_meson librsvg ${LIBRSVG_VER} \
    -Dtests=false \
    -Dintrospection=enabled \
    -Dpixbuf=enabled \
    -Dvala=disabled \
    -Ddocs=disabled
}

build_highway () {
  build_with_cmake highway ${HIGHWAY_VER} \
    -DBUILD_SHARED_LIBS=ON \
    -DHWY_ENABLE_TESTS=OFF \
    -DHWY_ENABLE_EXAMPLES=OFF
}

build_lcms2 () {
  build_with_configure lcms2 ${LCMS2_VER} --enable-shared --disable-static
}

build_libjxl () {
  build_with_cmake libjxl ${LIBJXL_VER} \
    -DBUILD_SHARED_LIBS=ON \
    -DBUILD_TESTING=OFF \
    -DJPEGXL_FORCE_SYSTEM_HWY=ON \
    -DJPEGXL_FORCE_SYSTEM_BROTLI=ON \
    -DJPEGXL_FORCE_SYSTEM_LCMS2=ON \
    -DJPEGXL_BUNDLE_LIBPNG=OFF \
    -DJPEGXL_ENABLE_SKCMS=OFF \
    -DJPEGXL_ENABLE_SJPEG=OFF \
    -DJPEGXL_ENABLE_FUZZERS=OFF \
    -DJPEGXL_ENABLE_TOOLS=OFF \
    -DJPEGXL_ENABLE_EXAMPLES=OFF \
    -DJPEGXL_ENABLE_DEVTOOLS=OFF \
    -DJPEGXL_ENABLE_PLUGINS=OFF \
    -DJPEGXL_ENABLE_OPENEXR=OFF \
    -DJPEGXL_ENABLE_VIEWERS=OFF \
    -DJPEGXL_ENABLE_BENCHMARK=OFF \
    -DJPEGXL_ENABLE_JNI=OFF \
    -DJPEGXL_ENABLE_JPEGLI=OFF \
    -DJPEGXL_ENABLE_DOXYGEN=OFF \
    -DJPEGXL_ENABLE_MANPAGES=OFF \
    -Wno-dev
}

build_libcap () {
  # libcap uses a plain Makefile (no configure/cmake/meson).
  # GOLANG=no skips the optional Go bindings (avoids needing Go);
  # RAISE_SETFCAP=no skips the privileged setcap step during install;
  # building only the libcap/ subdir avoids the progs and PAM module.
  if [ ! -f $BUILD_DIR/libcap/.my_done${MY_DONE_EXT} ]; then
    printf "\n ### building libcap (${LIBCAP_VER}) with make\n"
    rm -rf $BUILD_DIR/libcap
    cp -a $DEPS_DIR/libcap-${LIBCAP_VER} $BUILD_DIR/libcap || error
    cd $BUILD_DIR/libcap || error

    printf "  running make (see `mypwd`/my_make.log${MY_DONE_EXT}) ... "
    make -C libcap -j ${nthreads} lib=lib prefix=$PREFIX DYNAMIC=yes GOLANG=no > my_make.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_make.log${MY_DONE_EXT}"
    echo "done"

    printf "  running install (see `mypwd`/my_make_install.log${MY_DONE_EXT}) ... "
    make -C libcap install lib=lib prefix=$PREFIX DYNAMIC=yes GOLANG=no RAISE_SETFCAP=no > my_make_install.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_make_install.log${MY_DONE_EXT}"
    echo "done"
    do_cleans="$do_cleans `pwd`"

    cd $BUILD_DIR || error
    touch $BUILD_DIR/libcap/.my_done${MY_DONE_EXT}
  fi
}

build_bubblewrap () {
  # bubblewrap cranks -Werror=format=2, so newer GCC's bogus "%s is null"
  # format-overflow false-positive becomes a hard error. Demote it to a warning.
  CFLAGS="$CFLAGS -Wno-error=format-overflow" \
  build_with_meson bubblewrap ${BUBBLEWRAP_VER} -Dtests=false
}

# First glycin build runs before gtk4 exists, so the GTK 4 bindings
# (libglycin-gtk4) must be disabled here. The second build (build_glycin2),
# after gtk is built, enables them.
# Thumbnailer disabled: its libglycin-rebind-sys -sys crate uses pkg-config to
# find an installed glycin-2.pc, which doesn't exist pre-install, so it can't
# build in-tree. Coot doesn't need the standalone thumbnailer anyway.
build_glycin () {
  build_with_meson glycin ${GLYCIN_VER} -Dtests=false -Dloaders=glycin-image-rs,glycin-jxl,glycin-svg -Dlibglycin-gtk4=false -Dvapi=false -Dglycin-thumbnailer=false
}
build_glycin2 () {
  build_with_meson glycin ${GLYCIN_VER} -Dtests=false -Dloaders=glycin-image-rs,glycin-jxl,glycin-svg -Dlibglycin-gtk4=true -Dvapi=false -Dglycin-thumbnailer=false
}

# gdk_pixbuf is a dependency of glycin, so it needs to be built first before (and without) glycin
build_gdk_pixbuf () {
  build_with_meson gdk-pixbuf ${GDK_PIXBUF_VER} -Dtests=false -Dman=false -Dgtk_doc=false -Dinstalled_tests=false -Dglycin=disabled
}

# Gets rebuilt after glycin, so that glycin support is included.
build_gdk_pixbuf2 () {
  build_with_meson gdk-pixbuf ${GDK_PIXBUF_VER} -Dtests=false -Dman=false -Dgtk_doc=false -Dinstalled_tests=false -Dglycin=enabled
}

build_at_spi2_core () {
  # -Ddefault_bus=dbus-daemon keeps needs_systemd=false even when dbus-broker-launch is
  # present (Rocky/RHEL), so libsystemd becomes optional; if absent, dbus_broker_arg is
  # simply cleared and the build proceeds without systemd-devel on any distro.
  build_with_meson at-spi2-core ${AT_SPI2_CORE_VER} -Ddefault_bus=dbus-daemon
}

build_gtk () {
  build_with_meson gtk ${GTK_VER} -Dbroadway-backend=true -Dwin32-backend=false -Dmacos-backend=false \
    -Dmedia-gstreamer=disabled  -Dintrospection=enabled -Dvulkan=disabled -Dbuild-tests=false \
    -Dbuild-testsuite=false -Dbuild-examples=false -Dbuild-demos=false -Dprint-cups=disabled
}

# Adwaita icon theme — a pure data package (no compiled code). Meson here is just an
# install orchestrator: it copies the pre-built icon tree out of the tarball, creates
# X11 cursor-name symlinks, and runs gtk4-update-icon-cache as a post-install step.
build_adwaita_icon_theme () {
  build_with_meson adwaita-icon-theme ${ADWAITA_ICON_THEME_VER}
}

build_pygobject () {
  build_with_meson pygobject ${PYGOBJECT_VER} -Dtests=false
}

build_maeparser () {
  build_with_cmake maeparser ${MAEPARSER_VER} -DCMAKE_POLICY_VERSION_MINIMUM=3.5  \
  -DMAEPARSER_BUILD_TESTS=OFF
}

build_coordgen() {
  build_with_cmake coordgen ${COORDGEN_VER} -DCMAKE_POLICY_VERSION_MINIMUM=3.5  \
  -DCOORDGEN_BUILD_TESTS=OFF \
  -DCOORDGEN_BUILD_EXAMPLE=OFF \
  -DCOORDGEN_USE_MAEPARSER=ON \
  -DCOORDGEN_RIGOROUS_BUILD=OFF 
}

build_eigen () {
  build_with_cmake eigen ${EIGEN_VER} -DEIGEN_BUILD_DOC=OFF \
          -DEIGEN_BUILD_TESTING=OFF \
          -DEIGEN_BUILD_DEMOS=OFF
}

build_libogg () {
  build_with_cmake libogg ${LIBOGG_VER} -DBUILD_SHARED_LIBS=ON
}

build_libvorbis () {
  build_with_configure libvorbis ${LIBVORBIS_VER} --enable-shared --disable-static
}

 
build_rdkit () {
  build_with_cmake rdkit ${RDKIT_VER} -DRDK_BUILD_CAIRO_SUPPORT=ON \
  -DRDK_BUILD_INCHI_SUPPORT=ON \
  -DRDK_INSTALL_COMIC_FONTS=OFF \
  -DRDK_INSTALL_INTREE=OFF \
  -DRDK_BUILD_CPP_TESTS=OFF \
  -DRDK_INSTALL_STATIC_LIBS=OFF \
  -DRDK_USE_BOOST_SERIALIZATION=ON -DRDK_USE_BOOST_STACKTRACE=ON
}

build_mmdb2 () {
  # Legacy crystallographic lib: needs the old-Fortran flags (no longer set globally).
  FFLAGS="-std=f2008 -fallow-argument-mismatch" \
  build_with_configure mmdb2 ${MMDB_VER} --enable-shared
}

build_openblas () {
  # DYNAMIC_ARCH builds kernels for multiple CPU micro-architectures and selects
  # the best at runtime — works for both distributable and locally-tuned builds.
  build_with_cmake openblas ${OPENBLAS_VER} \
    -DBUILD_SHARED_LIBS=ON \
    -DDYNAMIC_ARCH=ON \
    -DBUILD_TESTING=OFF
}

build_gsl () {
  build_with_configure gsl ${GSL_VER}
}

build_gemmi () {
  build_with_cmake gemmi ${GEMMI_VER} -DBUILD_SHARED_LIBS=true
}

build_libccp4 () {
  additional_build_env_setup
  # Legacy crystallographic lib: needs the old-Fortran flags (no longer set globally).
  FFLAGS="-std=f2008 -fallow-argument-mismatch" \
  CFLAGS="$CFLAGS -Wno-incompatible-pointer-types -std=gnu17" \
  build_with_configure libccp4 ${LIBCCP4_VER} \
    --enable-shared --disable-static \
    --datadir=$PREFIX/share/ccp4
  for __f in ccp4c.pc ccp4f.pc
  do
    if [ -f $PREFIX/lib/pkgconfig/$__f ] && [ ! -f $PREFIX/lib/pkgconfig/lib$__f ]; then
      cp -p $PREFIX/lib/pkgconfig/$__f $PREFIX/lib/pkgconfig/lib$__f
    else
      true
    fi
  done
}

build_libssm () {
  additional_build_env_setup
  if [ ! -f $BUILD_DIR/libssm/.my_done${MY_DONE_EXT} ]; then
    printf "\n ### building libssm (${LIBSSM_VER}) with configure/make\n"
    rm -rf $BUILD_DIR/libssm
    cp -a $DEPS_DIR/libssm-${LIBSSM_VER} $BUILD_DIR/libssm || error
    cd $BUILD_DIR/libssm || error

    printf "  setting up libssm ... "
    ( aclocal && libtoolize --automake --copy && autoconf && automake --copy --add-missing --gnu ) > my_setup.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_setup.log${MY_DONE_EXT}"
    echo "done"

    # Explicit opt: a set CFLAGS suppresses autoconf's -O2 default (see build_with_configure).
    [ "$btype" = "debug" ] && __opt="-O2 -g" || __opt="-O2"
    printf "  configure libssm ... "
    CFLAGS="${CFLAGS} ${__opt}" CXXFLAGS="${CXXFLAGS} ${__opt}" \
    ./configure --prefix=$PREFIX \
      --enable-shared --disable-static \
      --enable-ccp4 > my_configure.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_configure.log${MY_DONE_EXT}"
      # unrecognized option
      #--with-mmdb=$PREFIX \
    echo "done"

    printf "  making libssm ... "
    make -j ${nthreads} > my_make.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_make.log${MY_DONE_EXT}"
    echo "done"

    printf "  installing libssm ... "
    make install > my_make_install.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_make_install.log${MY_DONE_EXT}"
    echo "done"
    do_cleans="$do_cleans `pwd`"

    cd $BUILD_DIR || error
    touch $BUILD_DIR/libssm/.my_done${MY_DONE_EXT}
  fi
}

build_libclipper () {
  additional_build_env_setup
  if [ ! -f $BUILD_DIR/libclipper/.my_done${MY_DONE_EXT} ]; then
    printf "\n ### building libclipper ($LIBCLIPPER_VER_PRE) with configure/make\n"
    mkdir -p $BUILD_DIR/libclipper || error
    cd $BUILD_DIR/libclipper || error
    rm -rf *
    printf "  patching libclipper ... "
    sed -i 's/from >> &word\[0\]/from >> word/' $DEPS_DIR/clipper-${LIBCLIPPER_VER_PRE}/clipper/cif/cif_data_io.cpp
    echo "done"
    printf "  configure clipper with FC=$FC CC=$CC CXX=$CXX ... "
    __dbg_flag=""
    [ "$btype" = "debug" ] && __dbg_flag="-g"
    CXXFLAGS="${__dbg_flag} -O2 -fno-strict-aliasing -Wno-narrowing -I$PREFIX/include" \
    CFLAGS="${__dbg_flag} -O2 -fno-strict-aliasing -Wno-narrowing -I$PREFIX/include" \
    FFLAGS="-std=f2008 -fallow-argument-mismatch" \
    $DEPS_DIR/clipper-${LIBCLIPPER_VER_PRE}/configure --prefix=$PREFIX \
      --enable-shared --disable-static \
      --enable-contrib --enable-ccp4 \
      --enable-cif --enable-mmdb --enable-minimol \
      --enable-cns --enable-phs --enable-fortran > my_configure.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_configure.log${MY_DONE_EXT}"
#    printf "  configure clipper with FC=$FC CC=$CC CXX=$CXX ... "
#    $DEPS_DIR/clipper-${LIBCLIPPER_VER_PRE}/configure --prefix=$PREFIX \
#      --enable-shared --disable-static \
#      --enable-contrib --enable-ccp4 \
#      --enable-cif --enable-mmdb --enable-minimol \
#      --enable-cns --enable-phs --enable-fortran > my_configure.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_configure.log${MY_DONE_EXT}"
##    printf "  configure clipper with FC=$FC CC=$CC CXX=$CXX ... "
##    CXXFLAGS="-O2 -fno-strict-aliasing -Wno-narrowing" \
##    $DEPS_DIR/clipper-${LIBCLIPPER_VER_PRE}/configure --prefix=$PREFIX \
##      --enable-shared --disable-static \
##      --enable-ccp4 \
##      --enable-cif --enable-mmdb --enable-minimol \
##      --build=x86_64-linux-gnu --disable-option-checking --disable-maintainer-mode --disable-dependency-tracking --enable-fortran > my_configure.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_configure.log${MY_DONE_EXT}"
#    $DEPS_DIR/clipper-${LIBCLIPPER_VER_PRE}/configure --prefix=$PREFIX \
#      --enable-shared --disable-static \
#      --enable-ccp4 \
#      --enable-cif --enable-mmdb --enable-minimol > my_configure.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_configure.log${MY_DONE_EXT}"
    echo "done"

    printf "  make clipper ... "
    make -j ${nthreads} > my_make.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_make.log${MY_DONE_EXT}"
    echo "done"

    printf "  installing clipper ... "
    make install > my_make_install.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_make_install.log${MY_DONE_EXT}"
    echo "done"
    do_cleans="$do_cleans `pwd`"

    cd $BUILD_DIR || error
    touch $BUILD_DIR/libclipper/.my_done${MY_DONE_EXT}
  fi
}

build_fftw () {
  #FFTW_CONFIGURE="./configure F77=gfortran${GCC_COMMAND_EXT} --prefix=$PREFIX --enable-shared --disable-static --enable-openmp --enable-threads --with-gcc --with-gnu-ld"
  FFTW_CONFIGURE="./configure F77=gfortran${GCC_COMMAND_EXT} --prefix=$PREFIX --enable-shared --disable-static --with-gcc --with-gnu-ld"
  # Explicit opt: a set CFLAGS suppresses autoconf's -O2 default (see build_with_configure).
  # Prefixed (quoted) on each call below so $FFTW_CONFIGURE still word-splits as before.
  [ "$btype" = "debug" ] && __opt="-O2 -g" || __opt="-O2"
  if [ ! -f $BUILD_DIR/fftw/.my_done${MY_DONE_EXT} ]; then
    printf "\n ### building fftw with configure/make ... "
    rm -rf $BUILD_DIR/fftw
    cp -a $DEPS_DIR/fftw-${FFTW_VER} $BUILD_DIR/fftw || error
    cd $BUILD_DIR/fftw || error
    CFLAGS="${CFLAGS} ${__opt}" ${FFTW_CONFIGURE} > my_configure.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_configure.log${MY_DONE_EXT}"
    make -j ${nthreads} > my_make.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_make.log${MY_DONE_EXT}"
    make install > my_make_install.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_make_install.log${MY_DONE_EXT}"
    do_cleans="$do_cleans `pwd`"
    cd $BUILD_DIR || error
    touch $BUILD_DIR/fftw/.my_done${MY_DONE_EXT}
    echo "done"
  fi

  if [ ! -f $BUILD_DIR/sfftw/.my_done${MY_DONE_EXT} ]; then
    printf "\n ### building sfftw with configure/make ... "
    rm -rf $BUILD_DIR/sfftw
    cp -a $DEPS_DIR/fftw-${FFTW_VER} $BUILD_DIR/sfftw || error
    cd $BUILD_DIR/sfftw || error
    CFLAGS="${CFLAGS} ${__opt}" ${FFTW_CONFIGURE} --enable-type-prefix --enable-float > my_configure.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_configure.log${MY_DONE_EXT}"
    make -j ${nthreads} > my_make.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_make.log${MY_DONE_EXT}"
    make install > my_make_install.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_make_install.log${MY_DONE_EXT}"
    do_cleans="$do_cleans `pwd`"
    cd $BUILD_DIR || error
    touch $BUILD_DIR/sfftw/.my_done${MY_DONE_EXT}
    echo "done"
  fi
}

# -------------------------------------------------------------------------------------
# other functions
do_wget () {
  # Arguments: URL [output-filename [max-retries]]
  __url=$1;shift
  if [ $# -ge 1 ]; then
    __output_file=$1;shift
  else
    __output_file=`basename $__url`
  fi
  if [ $# -ge 1 ]; then
    __max_retries=$1;shift
  else
    __max_retries=8
  fi

  # Derive a short package name used in the log filename (my_get_<pkg>.log).
  # Strip version numbers, dots, underscores, and a leading "- ", then take the first word.
  # e.g. "boost_1_82_0.tar.bz2" → "boost", "cmake-3.27.0.tar.gz" → "cmake"
  __pkg_name=`basename $__output_file | sed "s/[_.0-9]/ /g" | sed "s/- //g" | awk '{print $1}'`

  # Append this download call to a per-script debug log in /tmp for post-mortem tracing
  echo "do_wget \"$__pkg_name\" \"$__output_file\" \"$__url\"" >> /tmp/`basename ${0%.sh}`.debug

  if [ ! -f $__output_file ]; then
    # wget 2.x negotiates content-encoding and decompresses on the fly by default,
    # which corrupts binary archives; disable it to receive the raw bytes
    case `wget --version | awk '/^GNU/{print $3;exit}'` in
      2.*) __wget_cmd="wget --no-compression";;
      *) __wget_cmd="wget";;
    esac
    isuccess=0
    # --retry-on-host-error is not recognised on Fedora 40+ builds of wget; omit it there
    case `echo "$os" | tr '[A-Z]' '[a-z]'` in
      fedora-4[0-9]*) __wget_host_error_flag="";;
      *) __wget_host_error_flag="--retry-on-host-error";;
    esac
    __wget_common_flags="--retry-connrefused --retry-on-http-error=500,502,503,429  $__wget_host_error_flag --waitretry=2 --read-timeout=30 --timeout=45 -t 5"
    printf "\n getting $__output_file ... "

    # --- Three-tier download strategy ---
    # Tier 1: contrib mirror at the full relative path (fastest, avoids hammering upstream)
    __actual_source_url="${url_contrib}/$__output_file"
    $__wget_cmd $__wget_common_flags -O "$__output_file" ${url_contrib}/$__output_file > my_get_${__pkg_name}.log 2>&1
    if [ $? -ne 0 ] || [ ! -s $__output_file ]; then
      # ! -s: file missing or zero-length (i.e. partial/empty download)
      rm -fv "$__output_file" >> my_get_${__pkg_name}.log 2>&1

      # Tier 2: contrib mirror using only the URL's basename (handles path mismatches)
      __actual_source_url="${url_contrib}/`basename $__url`"
      $__wget_cmd $__wget_common_flags -O "$__output_file" ${url_contrib}/`basename $__url` >> my_get_${__pkg_name}.log 2>&1
      if [ $? -ne 0 ] || [ ! -s $__output_file ]; then
        rm -fv "$__output_file" >> my_get_${__pkg_name}.log 2>&1

        # Tier 3: original upstream URL, retried up to __max_retries times with linear back-off
        for __attempt in `seq 1 $__max_retries`
        do
          __actual_source_url="$__url"
          $__wget_cmd $__wget_common_flags -O "$__output_file" "$__url" >> my_get_${__pkg_name}.log 2>&1
          if [ $? -eq 0 ] && [ -s "$__output_file" ]; then
            isuccess=1
            break
          fi
          rm -fv "$__output_file" >> my_get_${__pkg_name}.log 2>&1
          if [ $__attempt -eq $__max_retries ]; then
            error "see `mypwd`/my_get_${__pkg_name}.log"
          fi
          # Linear back-off: 5s after attempt 1, 10s after attempt 2, etc.
          sleep `expr $__attempt \* 5`
        done
      else
        isuccess=1
      fi
    else
      isuccess=1
    fi
    echo "from \"$__actual_source_url\" ... done"
  fi

  if [ -f $__output_file ]; then
    case "$__output_file" in
      *.tar*|*.tgz)
        # List the archive, take the first entry, grab the path (last field), strip trailing slash.
        __tarball_top_dir=`tar -tvf "$__output_file" 2>&1 | head -n 1 | awk '{print $NF}' | sed "s%/.*%%"`
        if [ "X$__tarball_top_dir" = "X" ]; then
          ls -l "$__output_file"
          file "$__output_file"
          error "unable to understand (expected) tarball $__output_file"
        else
          if [ ! -d $__tarball_top_dir/ ]; then
            printf "   unpacking $__output_file ... "
            tar -xf "$__output_file"
            if [ $? -ne 0 ]; then
              ls -l "$__output_file"
              file "$__output_file"
              error "see above"
            fi
            echo "done"
            isuccess=1
          fi
        fi
        ;;
    esac
  else
    if [ $isuccess -eq 0 ]; then
      # make sure to remove any (partial) files ...
      rm -f $__output_file
    fi
  fi
  return 0
}

# download_toolchain — fetch (only) the bootstrap toolchain sources: Python, CMake,
# Ninja and the rustup installer. Pure downloads via do_wget, no compilation, so the
# whole download phase can run up-front before anything is built (this is what the
# -download-only phase calls). Mirrors download_dependencies. Safe to run standalone or
# repeatedly: do_wget is idempotent and skips anything already present.
download_toolchain () {
  mkdir -p $DEPS_DIR  || error
  mkdir -p $BUILD_DIR || error

  # Some distros ship ancient python. We need a fairly new version of pip and python.
  cd $DEPS_DIR || error
  do_wget https://www.python.org/ftp/python/${PYTHON_VER}/Python-${PYTHON_VER}.tar.xz
  if [ -d Python-${PYTHON_VER} ] && [ ! -d python-${PYTHON_VER} ]; then
    mv Python-${PYTHON_VER} python-${PYTHON_VER} && \
      ln -s python-${PYTHON_VER} Python-${PYTHON_VER} || error
  fi

  # Built in initial_setup before Python (which links them). Fetched here so the
  # toolchain phase is self-contained.
  do_wget https://ftp.gnu.org/gnu/ncurses/ncurses-${NCURSES_VER}.tar.gz
  do_wget https://ftp.gnu.org/gnu/readline/readline-${READLINE_VER}.tar.gz
  do_wget https://github.com/libffi/libffi/releases/download/v${LIBFFI_VER}/libffi-${LIBFFI_VER}.tar.gz
  do_wget https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VER}/openssl-${OPENSSL_VER}.tar.gz

  # zlib, zstd, brotli — built before Python (zipfile/gzip/pip) and OpenSSL
  # (compression support). System cmake is used for zstd/brotli.
  do_wget https://github.com/madler/zlib/releases/download/v${ZLIB_VER}/zlib-${ZLIB_VER}.tar.xz
  do_wget https://github.com/facebook/zstd/archive/refs/tags/v${ZSTD_VER}.tar.gz zstd-${ZSTD_VER}.tar.gz
  do_wget https://github.com/google/brotli/archive/refs/tags/v${BROTLI_VER}.tar.gz brotli-${BROTLI_VER}.tar.gz
  # bzip2 — shared library only; Python's _bz2 needs it
  do_wget https://sourceware.org/pub/bzip2/bzip2-${BZIP2_VER}.tar.gz
  # xz/liblzma — Python's _lzma needs it; also a NEEDED of libdw (elfutils) and libtiff
  do_wget https://github.com/tukaani-project/xz/releases/download/v${XZ_VER}/xz-${XZ_VER}.tar.gz

  # expat
  do_wget https://github.com/libexpat/libexpat/releases/download/R_`echo ${EXPAT_VER} | sed "s/\./_/g"`/expat-${EXPAT_VER}.tar.xz

  # sqlite — /2026/ is sqlite's release-year folder
  do_wget https://www.sqlite.org/2026/sqlite-autoconf-${SQLITE_SRCVER}.tar.gz
  if [ -d sqlite-autoconf-${SQLITE_SRCVER} ] && [ ! -d sqlite-${SQLITE_VER} ]; then
    mv sqlite-autoconf-${SQLITE_SRCVER} sqlite-${SQLITE_VER} && \
      ln -s sqlite-${SQLITE_VER} sqlite-autoconf-${SQLITE_SRCVER} || error
  fi

  # Newer CMake — unpacked under its build dir, where initial_setup bootstraps it.
  mkdir -p $BUILD_DIR/cmakebuild || error
  cd $BUILD_DIR/cmakebuild || error
  do_wget https://github.com/Kitware/CMake/archive/refs/tags/v${CMAKE_VER}.tar.gz cmake-${CMAKE_VER}.tar.gz

  # Newer Ninja
  mkdir -p $BUILD_DIR/ninjabuild || error
  cd $BUILD_DIR/ninjabuild || error
  do_wget https://github.com/ninja-build/ninja/archive/refs/tags/v${NINJA_VER}.tar.gz ninja-${NINJA_VER}.tar.gz

  # Rust installer (rustup-init.sh). Only the bootstrap script is fetched here; the
  # actual rustup/cargo-c install stays in initial_setup (it writes to CARGO_HOME).
  mkdir -p $DEPS_DIR/rust || error
  cd $DEPS_DIR/rust || error
  if [ ! -f rustup-init.sh ]; then
    do_wget https://sh.rustup.rs rustup-init.sh 8
    chmod +x rustup-init.sh || error
  fi

  cd $PREFIX || error
}

initial_setup () {
  # Subshell so this phase's build-flag env (CFLAGS/LDFLAGS from additional_build_env_setup)
  # can't leak into deps; `|| error` re-raises the subshell's exit, do_cleans is stashed via file.
  __cleans_file="$BUILD_DIR/.initial_setup_do_cleans"
  rm -f "$__cleans_file"
  (

  mkdir -p $PREFIX    || error
  mkdir -p $DEPS_DIR  || error
  mkdir -p $BUILD_DIR || error

  # Ensure the toolchain sources are present. No-op when the -download-only phase
  # already fetched them; this keeps -toolchain-only self-contained.
  download_toolchain || error

  cd $PREFIX || error

  # libffi, ncurses, readline, compression libs, openssl, expat and sqlite are linked by
  # Python (ctypes / _curses / readline / zipfile+gzip+bz2+lzma / ssl / pyexpat / _sqlite3,
  # plus pip's HTTPS) and must exist before it — built here, not in the deps phase.
  # additional_build_env_setup puts $PREFIX on the compiler -I/-L paths so readline finds ncurses.
  additional_build_env_setup
  build_ncurses  || error
  build_readline || error
  build_libffi   || error
  build_zlib     || error
  build_zstd     || error
  build_brotli   || error
  build_bzip2    || error
  build_xz       || error
  build_openssl  || error
  build_expat    || error
  build_sqlite   || error

  if [ ! -x $PREFIX/bin/python3 ]; then
    printf "\n"
    build_python || error
    # For Boost.Python to build
    ln -sf $PREFIX/bin/python3 $PREFIX/bin/python
    ln -sf $PREFIX/bin/pip3 $PREFIX/bin/pip
  fi

  if [ ! -f $PREFIX/.my_pip_install_done ]; then
    printf "\n pip installing meson et al (see `mypwd`/my_pip_install.log) ... "
    python3 -m pip install meson setuptools numpy==${NUMPY_VER} packaging nanobind requests xattr mako > my_pip_install.log 2>&1 || error "see `mypwd`/my_pip_install.log"
    echo "done"
    touch $PREFIX/.my_pip_install_done
  fi
  # Newer CMake (source fetched + unpacked by download_toolchain)
  if [ ! -f $BUILD_DIR/cmakebuild/.my_done ]; then
    printf "\n ### building newer CMake\n"
    mkdir -p $BUILD_DIR/cmakebuild || error
    cd $BUILD_DIR/cmakebuild || error
    cd CMake-${CMAKE_VER} || error

    printf "   bootstrapping CMake ... "
    ./bootstrap --prefix=$PREFIX > my_bootstrap.log 2>&1 || error "see `mypwd`/my_bootstrap.log"
    echo "done"

    printf "   building CMake ... "
    make -j ${nthreads} > my_make.log 2>&1 || error "see `mypwd`/my_make.log"
    echo "done"

    printf "   installing CMake ... "
    make install > my_make_install.log 2>&1 || error "see `mypwd`/my_make_install.log"
    echo "done"
    do_cleans="$do_cleans `pwd`"

    cd ${PREFIX} || error
    touch $BUILD_DIR/cmakebuild/.my_done
  fi

  # zlib/zstd/brotli already ran `cmake` (system one) earlier this phase, so the shell
  # hash-cached that path; without this the ninja build below and every deps-phase
  # build_with_cmake would keep using the old system cmake instead of the one just built.
  hash -r 2>/dev/null || true

  # Newer Ninja (source fetched + unpacked by download_toolchain)
  if [ ! -f $BUILD_DIR/ninjabuild/.my_done ]; then
    printf "\n ### building newer Ninja\n"
    mkdir -p $BUILD_DIR/ninjabuild || error
    cd $BUILD_DIR/ninjabuild || error
    cd ninja-${NINJA_VER} || error

    printf "   running cmake ... "
    cmake -Bbuild-cmake -DCMAKE_INSTALL_PREFIX=$PREFIX > my_cmake.log 2>&1 || error "see `mypwd`/my_cmake.log"
    echo "done"

    printf "   running build ... "
    cmake --build build-cmake -j ${nthreads} > my_cmake_build.log 2>&1 || error "see `mypwd`/my_cmake_build.log"
    echo "done"

    printf "   running install ... "
    cmake --install build-cmake > my_cmake_install.log 2>&1 || error "see `mypwd`/my_cmake_install.log"
    echo "done"
    do_cleans="$do_cleans `pwd`"

    cd ${PREFIX} || error
    touch $BUILD_DIR/ninjabuild/.my_done
  fi

  # Rust for librsvg (rustup-init.sh is fetched by download_toolchain). rustup installs
  # into $HOME by default; we override that to $PREFIX via RUSTUP_HOME and CARGO_HOME.
  # Guard on the installed cargo binary (not the presence of the installer script, which
  # download_toolchain already put in place).
  if [ ! -x $CARGO_HOME/bin/cargo ]; then
    printf "\n### Installing RUST (into CARGO_HOME=$CARGO_HOME, RUSTUP_HOME=$RUSTUP_HOME)\n"
    cd $DEPS_DIR/rust || error
    RUSTUP_INIT_SKIP_PATH_CHECK=yes ./rustup-init.sh --profile default -y --no-modify-path > $DEPS_DIR/rust/my_rust_install.log 2>&1 || error "see $DEPS_DIR/rust/my_rust_install.log"
    cd $PREFIX || error
  fi

  # librsvg's Meson build drives cargo-c (cargo cbuild / cinstall) to produce the C-ABI
  # library plus its .pc file and headers; rustup does not ship it, so install the
  # cargo-cbuild subcommand into CARGO_HOME. (https://github.com/lu-zero/cargo-c)
  if [ ! -x $CARGO_HOME/bin/cargo-cbuild ]; then
    printf "\n### Installing cargo-c into CARGO_HOME=$CARGO_HOME ... "
    $CARGO_HOME/bin/cargo install cargo-c --locked > $DEPS_DIR/rust/my_cargo_c_install.log 2>&1 || error "see $DEPS_DIR/rust/my_cargo_c_install.log"
    echo "done"
  fi

  printf '%s' "$do_cleans" > "$__cleans_file" || error
  ) || error
  [ -f "$__cleans_file" ] && { do_cleans=`cat "$__cleans_file"`; rm -f "$__cleans_file"; }
}

setup_build_env () {
  export PKG_CONFIG_LIBDIR=$PREFIX/lib/x86_64-linux-gnu:$PREFIX/lib64:$PREFIX/lib:/usr/lib/x86_64-linux-gnu:/usr/lib64:/usr/lib
  export PKG_CONFIG_PATH=$PREFIX/lib/x86_64-linux-gnu/pkgconfig:$PREFIX/lib64/pkgconfig:$PREFIX/lib/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:$PREFIX/share/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig
  export PATH="$CARGO_HOME/bin:$PREFIX/bin:$PATH"
  export LD_LIBRARY_PATH="$PREFIX/lib/x86_64-linux-gnu:$PREFIX/lib64:$PREFIX/lib"
  export LD_PATH="$PREFIX/lib/x86_64-linux-gnu:$PREFIX/lib64:$PREFIX/lib"
  export ACLOCAL_PATH="$PREFIX/share/aclocal"
  export CMAKE_PREFIX_PATH="$PREFIX"
  export GI_TYPELIB_PATH="$PREFIX/lib/girepository-1.0:$PREFIX/lib64/girepository-1.0"
  export CMAKE_BUILD_PARALLEL_LEVEL=${nthreads}
  # Resilience for cargo's crates.io downloads. MULTIPLEXING=false drops HTTP/2 (one
  # request per connection), sidestepping the recurring "[16] HTTP2 framing layer"
  # error that retries alone can't fix. Hits cargo-c install and librsvg's cargo cbuild.
  export CARGO_NET_RETRY=40
  export CARGO_HTTP_MULTIPLEXING=false

  # Our from-source OpenSSL shadows the system libssl (via LD_LIBRARY_PATH) but ships no
  # cert store; point TLS tools (wget, rustup, pip) at the build host's CA bundle so HTTPS
  # still verifies. coot-env.sh does the same for the shipped tarball at runtime.
  if [ "X$SSL_CERT_FILE" = "X" ]; then
    for __ca in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt \
                /etc/ssl/ca-bundle.pem /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem \
                /etc/ssl/cert.pem; do
      [ -f "$__ca" ] && { export SSL_CERT_FILE="$__ca"; break; }
    done
  fi
  [ -d /etc/ssl/certs ] && export SSL_CERT_DIR=/etc/ssl/certs
  [ "X$SSL_CERT_FILE" != "X" ] && export CURL_CA_BUNDLE="$SSL_CERT_FILE"

  # Our from-source libxml2 defaults its catalog to $PREFIX/etc/xml/catalog (empty); point it
  # at the host's so xmlto/xmllint resolve DocBook DTDs locally instead of fetching over HTTP.
  [ "X$XML_CATALOG_FILES" = "X" ] && [ -f /etc/xml/catalog ] && export XML_CATALOG_FILES=/etc/xml/catalog

  # GCC_COMMAND_EXT is an optional version suffix set in the distro config (e.g. "-13" → gcc-13).
  # Only set CC/CXX/FC/F77 when the caller hasn't already provided them.
  # `type` prints where the compiler was found (e.g. "gcc is /usr/bin/gcc").
  # sed "s/^/ # CC  : /" inserts " # CC  : " at the start of every line (^ matches
  # the beginning of the line without consuming any characters, so the substitution
  # is purely an insertion). This makes the output appear as a comment in the build log.
  if [ "X$CC" = "X" ]; then
    CC=gcc${GCC_COMMAND_EXT}
    type $CC  2>&1 | sed "s/^/ # CC  : /" || error
    [ $do_distributable -eq 1 ] && CC="$CC -mtune=generic" || CC="$CC -march=native -mtune=native"
  fi
  export CC
  echo " # CC=\"$CC\""

  if [ "X$CXX" = "X" ]; then
    CXX=g++${GCC_COMMAND_EXT}
    type $CXX 2>&1 | sed "s/^/ # CXX : /" || error
    [ $do_distributable -eq 1 ] && CXX="$CXX -mtune=generic" || CXX="$CXX -march=native -mtune=native"
  fi
  export CXX
  echo " # CXX=\"$CXX\""

  if [ "X$FC" = "X" ]; then
    FC=gfortran${GCC_COMMAND_EXT}
    type $FC  2>&1 | sed "s/^/ # FC  : /" || error
    [ $do_distributable -eq 1 ] && FC="$FC -mtune=generic" || FC="$FC -march=native -mtune=native"
  fi
  export FC
  echo " # FC=\"$FC\""

  if [ "X$F77" = "X" ]; then
    F77="$FC" # for libccp4
  fi
  export F77

  #export FC=gfortran-10
  export PYTHONPATH=$PREFIX/lib64/python${PYTHON_VER_MAJOR}.${PYTHON_VER_MINOR}/lib-dynload

  printf "\n"
}

additional_build_env_setup () {
  # No FFLAGS here: the legacy crystallographic libs (mmdb2/libccp4/libclipper) that need
  # "-std=f2008 -fallow-argument-mismatch" set it themselves. Exporting it globally broke
  # the cmake Fortran checks in eigen/openblas.
  export CFLAGS="-I${PREFIX}/include"
  export CXXFLAGS="-I${PREFIX}/include"
  IFS=":"
  # IFS is ":" so PKG_CONFIG_LIBDIR is split on colons into individual directories
  for pkgconfig_dir in $PKG_CONFIG_LIBDIR
  do
    case $pkgconfig_dir in
      # Only add directories that live under our prefix (skip standard system paths)
      ${PREFIX}/*)
        # grep -c returns 0 if the flag is absent; surrounding spaces prevent partial matches (e.g. -L/foo matching -L/foobar)
        [ `echo " $LDFLAGS " | grep -c " -L${pkgconfig_dir} "` -eq 0 ] && export LDFLAGS="-L${pkgconfig_dir} ${LDFLAGS}";;
    esac
  done
  unset IFS
  export GLM_CFLAGS="-I${PREFIX}/include"
  export GLM_LIBS="-L${PREFIX}/lib"
}



download_dependencies () {
  cd $DEPS_DIR || error

  # util-linux (for libmount). Unpacks to util-linux-${UTIL_LINUX_VER} (used as-is).
  do_wget https://www.kernel.org/pub/linux/utils/util-linux/v`echo ${UTIL_LINUX_VER} | cut -d. -f1-2`/util-linux-${UTIL_LINUX_VER}.tar.xz

  # ICU (icu4c) — unpacks to icu/; rename so the source dir is icu-${ICU_VER}
  # (symlink left behind so do_wget doesn't re-unpack on reruns).
  do_wget https://github.com/unicode-org/icu/releases/download/release-${ICU_VER}/icu4c-${ICU_VER}-sources.tgz icu4c-${ICU_VER}-sources.tgz
  if [ -d icu ] && [ ! -d icu-${ICU_VER} ]; then
    mv icu icu-${ICU_VER} && \
      ln -s icu-${ICU_VER} icu || error
  fi

  # libxml2 — provides xmllint for shared-mime-info
  do_wget https://gitlab.gnome.org/GNOME/libxml2/-/archive/v${LIBXML2_VER}/libxml2-v${LIBXML2_VER}.tar.bz2
  if [ -d libxml2-v${LIBXML2_VER} ] && [ ! -d libxml2-${LIBXML2_VER} ]; then
    mv libxml2-v${LIBXML2_VER} libxml2-${LIBXML2_VER} && \
      ln -s libxml2-${LIBXML2_VER} libxml2-v${LIBXML2_VER} || error
  fi

  #Libjpeg
  do_wget https://github.com/libjpeg-turbo/libjpeg-turbo/archive/refs/tags/${LIBJPEG_VER}.tar.gz libjpeg-turbo-${LIBJPEG_VER}.tar.gz

  #Glib
  do_wget https://gitlab.gnome.org/GNOME/glib/-/archive/${GLIB_VER}/glib-${GLIB_VER}.tar.gz
  # Override glib packaging issue
  if [ -d glib-${GLIB_VER}/subprojects/gvdb ]; then
    rm -rf glib-${GLIB_VER}/subprojects/gvdb
  fi

  #GObject-introspection
  do_wget https://download.gnome.org/sources/gobject-introspection/${GOBJECT_INTROSPECTION_VER_MM}/gobject-introspection-${GOBJECT_INTROSPECTION_VER}.tar.xz
  if [ -d gobject-introspection-${GOBJECT_INTROSPECTION_VER} ] && [ ! -d gobject_introspection-${GOBJECT_INTROSPECTION_VER} ]; then
    mv gobject-introspection-${GOBJECT_INTROSPECTION_VER} gobject_introspection-${GOBJECT_INTROSPECTION_VER} && \
      ln -s gobject_introspection-${GOBJECT_INTROSPECTION_VER} gobject-introspection-${GOBJECT_INTROSPECTION_VER} || error
  fi

  ### https://ftp.gnu.org/pub/gnu/
  ### https://ftp.fau.de/gnu/
  
  for __p in guile gsl libunistring
  do
    __puc=`echo $__p | tr '[a-z]' '[A-Z]'`
    eval "__v=\"\$${__puc}_VER\""  
    #do_wget https://ftp.gnu.org/pub/gnu/${__p}/${__p}-${__v}.tar.gz
    do_wget https://ftp.fau.de/gnu/${__p}/${__p}-${__v}.tar.gz
  done

  # SWIG
  do_wget https://deac-fra.dl.sourceforge.net/project/swig/swig/swig-${SWIG_VER}/swig-${SWIG_VER}.tar.gz
  #do_wget https://downloads.sourceforge.net/swig/swig-${SWIG_VER}.tar.gz
  #do_wget https://downloads.sourceforge.net/swig/swig-${SWIG_VER}/swig-${SWIG_VER}.tar.gz

  # Boost's CMake archive (the b2 release tarball has no CMakeLists.txt); unpacks to
  # boost-<ver>-<rev>, symlink to boost-<ver> for build_with_cmake's source path.
  do_wget https://github.com/boostorg/boost/releases/download/boost-${BOOST_VER}-${BOOST_CMAKE_REV}/boost-${BOOST_VER}-${BOOST_CMAKE_REV}-cmake.tar.xz
  if [ -d boost-${BOOST_VER}-${BOOST_CMAKE_REV} ] && [ ! -e boost-${BOOST_VER} ]; then
    ln -s boost-${BOOST_VER}-${BOOST_CMAKE_REV} boost-${BOOST_VER} || error
  fi

  # Libpng
  do_wget https://download.sourceforge.net/libpng/libpng-${LIBPNG_VER}.tar.xz libpng-${LIBPNG_VER}.tar.xz

  # Freetype2
  #   This one is a special snowflake which really likes to fail...
  do_wget https://download.savannah.gnu.org/releases/freetype/freetype-${FREETYPE_VER}.tar.xz freetype-${FREETYPE_VER}.tar.xz 15
  
  # Fontconfig
  #do_wget https://www.freedesktop.org/software/fontconfig/release/fontconfig-${FONTCONFIG_VER}.tar.xz
  do_wget https://codeload.github.com/fontconfig/fontconfig/tar.gz/refs/tags/${FONTCONFIG_VER} fontconfig-${FONTCONFIG_VER}.tar.gz

  # Fonts — kept together under $DEPS_DIR/fonts/ so CI can preserve/cache that one dir
  # (extract_fonts untars them in the Coot phase). do_wget's error() only kills the
  # subshell here, so guard the block with || error to keep abort-on-failure.
  ( mkdir -p $DEPS_DIR/fonts && cd $DEPS_DIR/fonts || error
    do_wget https://github.com/rsms/inter/releases/download/v${FONTS_INTER_VER}/Inter-${FONTS_INTER_VER}.tar.gz
    do_wget https://download.jetbrains.com/fonts/JetBrainsMono-${FONTS_JETBRAINS_VER}.tar.gz
    do_wget https://github.com/dejavu-fonts/dejavu-fonts/releases/download/version_`echo ${FONTS_DEJAVU_VER} | sed "s/\./_/g"`/dejavu-fonts-ttf-${FONTS_DEJAVU_VER}.tar.bz2
    do_wget https://github.com/dejavu-fonts/dejavu-fonts/releases/download/version_`echo ${FONTS_DEJAVU_VER} | sed "s/\./_/g"`/dejavu-lgc-fonts-ttf-${FONTS_DEJAVU_VER}.tar.bz2
    do_wget https://github.com/notofonts/NotoSansMono/archive/refs/heads/Noto.tar.gz ) || error

  # Pixman
  do_wget https://www.cairographics.org/releases/pixman-${PIXMAN_VER}.tar.gz

  # Libtiff
  do_wget https://gitlab.com/libtiff/libtiff/-/archive/v${LIBTIFF_VER}/libtiff-v${LIBTIFF_VER}.tar.gz

  # Poppler
  do_wget https://poppler.freedesktop.org/poppler-${POPPLER_VER}.tar.xz

  # Curl
  do_wget https://github.com/curl/curl/releases/download/curl-`echo ${CURL_VER} | sed "s%\.%_%g"`/curl-${CURL_VER}.tar.gz
  
  # Cairo
  do_wget https://cairographics.org/releases/cairo-${CAIRO_VER}.tar.xz

  # FriBidi
  do_wget https://github.com/fribidi/fribidi/releases/download/v${FRIBIDI_VER}/fribidi-${FRIBIDI_VER}.tar.xz

  # Pango
  do_wget https://download.gnome.org/sources/pango/${PANGO_VER_MM}/pango-${PANGO_VER}.tar.xz

  # Librsvg
  do_wget https://gitlab.gnome.org/GNOME/librsvg/-/archive/${LIBRSVG_VER}/librsvg-${LIBRSVG_VER}.tar.gz

  # Highway
  do_wget https://github.com/google/highway/archive/refs/tags/${HIGHWAY_VER}.tar.gz highway-${HIGHWAY_VER}.tar.gz

  # Little-CMS (lcms2)
  do_wget https://github.com/mm2/Little-CMS/releases/download/lcms${LCMS2_VER}/lcms2-${LCMS2_VER}.tar.gz

  # libjxl
  do_wget https://github.com/libjxl/libjxl/archive/refs/tags/v${LIBJXL_VER}.tar.gz libjxl-${LIBJXL_VER}.tar.gz

  # libcap
  do_wget https://www.kernel.org/pub/linux/libs/security/linux-privs/libcap2/libcap-${LIBCAP_VER}.tar.xz

  # Bubblewrap
  do_wget https://github.com/containers/bubblewrap/releases/download/v${BUBBLEWRAP_VER}/bubblewrap-${BUBBLEWRAP_VER}.tar.xz

  # Glycin
  do_wget https://gitlab.gnome.org/GNOME/glycin/-/archive/${GLYCIN_VER}/glycin-${GLYCIN_VER}.tar.bz2

  # GDK-Pixbuf
  do_wget https://download.gnome.org/sources/gdk-pixbuf/${GDK_PIXBUF_VER_MM}/gdk-pixbuf-${GDK_PIXBUF_VER}.tar.xz

  # at-spi2-core
  do_wget https://gitlab.gnome.org/GNOME/at-spi2-core/-/archive/${AT_SPI2_CORE_VER}/at-spi2-core-${AT_SPI2_CORE_VER}.tar.bz2 
  
  # Gtk
  do_wget https://download.gnome.org/sources/gtk/${GTK_VER_Major}.${GTK_VER_Minor}/gtk-${GTK_VER}.tar.xz

  # Adwaita icon theme
  do_wget https://download.gnome.org/sources/adwaita-icon-theme/${ADWAITA_ICON_THEME_VER_MAJOR}/adwaita-icon-theme-${ADWAITA_ICON_THEME_VER}.tar.xz

  # PyGObject
  do_wget https://github.com/GNOME/pygobject/archive/refs/tags/${PYGOBJECT_VER}.tar.gz pygobject-${PYGOBJECT_VER}.tar.gz

  # RDKit
  do_wget https://github.com/rdkit/rdkit/archive/refs/tags/Release_${RDKIT_VER}.tar.gz
  if [ -d rdkit-Release_${RDKIT_VER} ] && [ ! -d rdkit-${RDKIT_VER} ]; then
    mv rdkit-Release_${RDKIT_VER} rdkit-${RDKIT_VER} && \
      ln -s rdkit-${RDKIT_VER} rdkit-Release_${RDKIT_VER} || error
  fi

  # MMDB
  do_wget https://www2.mrc-lmb.cam.ac.uk/personal/pemsley/coot/dependencies/mmdb2-${MMDB_VER}.tar.gz

  # GEMMI
  do_wget https://github.com/project-gemmi/gemmi/archive/refs/tags/v${GEMMI_VER}.tar.gz gemmi-${GEMMI_VER}.tar.gz

  # Libccp4
  do_wget https://www2.mrc-lmb.cam.ac.uk/personal/pemsley/coot/dependencies/libccp4-${LIBCCP4_VER}.tar.gz

  # Libssm
  do_wget https://www2.mrc-lmb.cam.ac.uk/personal/pemsley/coot/dependencies/ssm-${LIBSSM_VER}.tar.gz libssm-${LIBSSM_VER}.tar.gz
  if [ -d ssm-${LIBSSM_VER} ] && [ ! -d libssm-${LIBSSM_VER} ]; then
    mv ssm-${LIBSSM_VER} libssm-${LIBSSM_VER} && \
      ln -s libssm-${LIBSSM_VER} ssm-${LIBSSM_VER} || error
  fi

  ## This is some patch from the AUR. I don't know what it fixes
  ## But I guess we need it.
  do_wget "https://aur.archlinux.org/cgit/aur.git/plain/ssm.pc.in?h=libssm" ssm.pc.in 8
  cp -p ssm.pc.in libssm-${LIBSSM_VER}/ssm.pc.in || error

  # Libclipper
  do_wget https://deb.debian.org/debian/pool/main/c/clipper/clipper_${LIBCLIPPER_VER}.orig.tar.gz libclipper-${LIBCLIPPER_VER}.tar.gz
  #do_wget https://www2.mrc-lmb.cam.ac.uk/personal/pemsley/coot/dependencies/clipper-${LIBCLIPPER_VER}.tar.gz libclipper-${LIBCLIPPER_VER}.tar.gz

  # OpenBLAS (BLAS + LAPACK, built from source for relocatability)
  do_wget https://github.com/OpenMathLib/OpenBLAS/releases/download/v${OPENBLAS_VER}/OpenBLAS-${OPENBLAS_VER}.tar.gz
  if [ -d OpenBLAS-${OPENBLAS_VER} ] && [ ! -d openblas-${OPENBLAS_VER} ]; then
    mv OpenBLAS-${OPENBLAS_VER} openblas-${OPENBLAS_VER} && \
      ln -s openblas-${OPENBLAS_VER} OpenBLAS-${OPENBLAS_VER} || error
  fi

  # FFTW
  do_wget http://www.fftw.org/fftw-${FFTW_VER}.tar.gz

  # gc
  # hboehm.info only carries tarballs up to 8.2.8; newer releases are on GitHub.
  do_wget https://github.com/bdwgc/bdwgc/releases/download/v${GC_VER}/gc-${GC_VER}.tar.gz gc-${GC_VER}.tar.gz 10

  #### github

  # glm
  do_wget https://github.com/g-truc/glm/archive/refs/tags/${GLM_VER}.tar.gz glm-${GLM_VER}.tar.gz

  # pcre2
  do_wget https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${PCRE2_VER}/pcre2-${PCRE2_VER}.tar.gz

  # Libepoxy
  do_wget https://github.com/anholt/libepoxy/archive/refs/tags/${LIBEPOXY_VER}.tar.gz libepoxy-${LIBEPOXY_VER}.tar.gz

  # Graphene
  do_wget https://github.com/ebassi/graphene/archive/refs/tags/${GRAPHENE_VER}.tar.gz graphene-${GRAPHENE_VER}.tar.gz

  # Harfbuzz
  do_wget https://github.com/harfbuzz/harfbuzz/archive/refs/tags/${HARFBUZZ_VER}.tar.gz harfbuzz-${HARFBUZZ_VER}.tar.gz

  # # elfutils
  do_wget https://sourceware.org/ftp/elfutils/${ELFUTILS_VER}/elfutils-${ELFUTILS_VER}.tar.bz2

  # libdwarf
  do_wget https://github.com/davea42/libdwarf-code/releases/download/v${LIBDWARF_VER}/libdwarf-${LIBDWARF_VER}.tar.xz

  # backward-cpp (stacktrace library for debug builds)
  do_wget https://github.com/bombela/backward-cpp/archive/refs/tags/v${LIBBACKWARD_VER}.tar.gz backward-cpp-${LIBBACKWARD_VER}.tar.gz
  if [ -d backward-cpp-${LIBBACKWARD_VER} ] && [ ! -d libbackward-${LIBBACKWARD_VER} ]; then
    mv backward-cpp-${LIBBACKWARD_VER} libbackward-${LIBBACKWARD_VER} && \
      ln -s libbackward-${LIBBACKWARD_VER} backward-cpp-${LIBBACKWARD_VER} || error
  fi

  # Shared-mime-info
  do_wget https://gitlab.freedesktop.org/xdg/shared-mime-info/-/archive/${SMI_VER}/shared-mime-info-${SMI_VER}.tar.gz
  
  # Wayland
  do_wget https://gitlab.freedesktop.org/wayland/wayland/-/archive/${WAYLAND_VER}/wayland-${WAYLAND_VER}.tar.gz

  do_wget https://gitlab.freedesktop.org/wayland/wayland-protocols/-/releases/${WAYLANDPROTOCOLS_VER}/downloads/wayland-protocols-${WAYLANDPROTOCOLS_VER}.tar.xz

  # Maeparser
  do_wget https://github.com/schrodinger/maeparser/archive/refs/tags/v${MAEPARSER_VER}.tar.gz maeparser-${MAEPARSER_VER}.tar.gz

  # Coordgen
  do_wget https://github.com/schrodinger/coordgenlibs/archive/refs/tags/v${COORDGEN_VER}.tar.gz coordgenlibs-${COORDGEN_VER}.tar.gz
  if [ -d coordgenlibs-${COORDGEN_VER} ] && [ ! -d coordgen-${COORDGEN_VER} ]; then
    mv coordgenlibs-${COORDGEN_VER} coordgen-${COORDGEN_VER} && \
    ln -s coordgen-${COORDGEN_VER} coordgenlibs-${COORDGEN_VER} || error
  fi

  # Eigen
  do_wget https://gitlab.com/libeigen/eigen/-/archive/${EIGEN_VER}/eigen-${EIGEN_VER}.tar.gz

  # libogg
  do_wget https://downloads.xiph.org/releases/ogg/libogg-${LIBOGG_VER}.tar.xz

  # libvorbis
  do_wget https://downloads.xiph.org/releases/vorbis/libvorbis-${LIBVORBIS_VER}.tar.xz
}

build_dependencies () {
  # Put $PREFIX on the compiler -I/-L paths up front so even the earliest configure deps
  # (util_linux, elfutils) link OUR zlib/zstd/bzip2/lzma rather than the system copies.
  additional_build_env_setup
  # order matters - and some have to be done multiple times it seems
  for dep in $BUILD_DEPENDENCIES
  do
    # Variable names can't contain hyphens; strip them to form a valid shell identifier
    dep_varname=`echo $dep | sed "s/-//g"`
    # Retrieve how many times this dependency has been built so far (0 if first time)
    eval "build_count=\$build_count_${dep_varname}"
    [ "X$build_count" = "X" ] && build_count=0
    build_count=`expr $build_count + 1`
    case $build_count in
      1) retry_suffix="";;
      *) retry_suffix=" again (#$build_count)";export MY_DONE_EXT=$build_count;;
    esac
    [ ! -f $BUILD_DIR/$dep/.my_done${MY_DONE_EXT} ] && [ $iverb -gt 0 ] && printf "\n >>> building $dep${retry_suffix}\n"
    # First build calls build_<dep>; subsequent builds call build_<dep>2, build_<dep>3, etc.
    # (${build_count#1} strips the leading "1", yielding "" for 1, "2" for 2, etc.)
    eval "build_${dep}${build_count#1}" || error
    eval "build_count_${dep_varname}=\$build_count"
    unset MY_DONE_EXT
  done
}

download_coot () {
  cd $COOT_DOWNLOAD_DIR
  if [ ! -d ${COOT_DIR} ]; then
    if [ "X$COOT_TAG" != "X" ]; then
      printf " ### Coot [${COOT_TAG}]: git clone (see `mypwd`/my_git_clone.log) ... "
      git clone --depth 1 --branch ${COOT_TAG} ${COOT_GIT}.git ${COOT_DIR} > my_git_clone.log 2>&1 || error "see `mypwd`/my_git_clone.log"
    elif [ "X$COOT_BRANCH" != "X" ]; then
      printf " ### Coot [${COOT_BRANCH}]: git clone (see `mypwd`/my_git_clone.log) ... "
      git clone --depth 1 --single-branch --branch ${COOT_BRANCH} ${COOT_GIT}.git ${COOT_DIR} > my_git_clone.log 2>&1 || error "see `mypwd`/my_git_clone.log"
    else
      error "unclear how to get Coot sources (COOT_TAG=\"$COOT_TAG\" and COOT_BRANCH=\"$COOT_BRANCH\") via git ... ?"
    fi
    echo "done"
  else
    printf " ### Coot: reusing existing github clone \"coot\"\n"
  fi
}

build_coot () {
  cd $COOT_BUILD_DIR
  additional_build_env_setup

  # some additional settings
  LDFLAGS="$LDFLAGS -lpython${PYTHON_VER_MAJOR}.${PYTHON_VER_MINOR} -lpthread -ldl -lutil -lm"
  [ `ls $PREFIX/lib*/libpixman-1.so 2>/dev/null | wc -l` -gt 0 ] && LDFLAGS="$LDFLAGS -lpixman-1"

  if [ "X$patch_file" != "X" ] && [ -f "$patch_file" ]; then
    if [ ! -f .my_patch_done ]; then
      type patch >/dev/null 2>&1
      [ $? -ne 0 ] && error "command \"patch\" not found (to apply \"$patch_file\" in directory \"$COOT_BUILD_DIR\""
      patch -p1 < "$patch_file" | awk '{print "     ",$0}' || error
    fi
  fi
  
  if [ ! -f .my_autogen_done ]; then
    printf " ### Coot: autogen.sh (see `mypwd`/my_autogen.log) ... "
    ./autogen.sh > my_autogen.log 2>&1 || error "see `mypwd`/my_autogen.log"
    echo "done"
    touch .my_autogen_done
    rm -f .my_configure_done
  fi
  # libdw is always passed; backward (stacktrace) is conditional on -debug
  [ "$btype" = "debug" ] && __with_backward="--with-backward" || __with_backward=""
  if [ ! -f .my_configure_done ]; then
    printf " ### Coot: configure (see `mypwd`/my_configure.log) ... "
    [ $do_distributable -eq 1 ] && __arch="-mtune=generic" || __arch="-march=native -mtune=native"
    case $btype in
      debug) __opt="-g -Og";;
      opt) __opt="-O3";;
      *) __opt="";;
    esac
    cat <<EOF > my_configure.sh
#!/bin/sh

PREFIX=$PREFIX
FFLAGS="$FFLAGS" \\
CFLAGS="$CFLAGS" \\
LDFLAGS="$LDFLAGS" \\
SHELL=/bin/sh \\
PYTHON=python3 \\
CXXFLAGS="${CXXFLAGS} ${__opt} ${__arch} -Wreturn-type -Wl,--as-needed -Wno-sequence-point -Wsign-compare -Wno-unknown-pragmas" \\
./configure --prefix=\$PREFIX \\
            --libexecdir=\$PREFIX/libexec \\
            --disable-static \\
            --with-sound \\
            --with-enhanced-ligand-tools \\
            --with-rdkit-prefix=\$PREFIX \\
            --with-boost=\$PREFIX \\
            --with-gemmi=\$PREFIX \\
            --with-libdw=\$PREFIX \\
            ${__with_backward} \\
            --with-boost-thread=boost_thread \\
            --with-boost-python="boost_python${PYTHON_VER_MAJOR}${PYTHON_VER_MINOR}"
EOF
    chmod +x my_configure.sh
    # run the very script we just wrote — single source of truth, no duplicate inline copy
    sh my_configure.sh > my_configure.log 2>&1 || error "see `mypwd`/my_configure.log"
    echo "done"
    touch .my_configure_done
    rm -f .my_make_done
  fi
  if [ ! -f .my_make_done1 ]; then
    sed -i "`grep -n \"BOOST_CPPFLAGS =\" $COOT_BUILD_DIR/pyrogen/Makefile | cut -f1 -d:`s/-pthread//" $COOT_BUILD_DIR/pyrogen/Makefile || error

    env | sort > .env_current || error
    if [ -f $PREFIX/.env_start ]; then
      [ -f .env_mod ] && rm .env_mod
      rm -f .env_mod
      # find all new settings:
      for __v in `grep "^[A-Z].*=" .env_current | cut -f1 -d'=' | egrep "^LD_|^PATH|^PYTHON"`
      do
        if [ `grep -c "^${__v}=" $PREFIX/.env_start` -eq 0 ]; then
          eval "__vv=\"\$$__v\""
          [ "X$__vv" != "X" ] && echo "export $__v=\"$__vv\"" >> .env_mod
        fi
      done
      # find all modified settings:
      for __v in `grep "^[A-Z].*=" .env_current | cut -f1 -d'=' | egrep "^LD_|^PATH|^PYTHON"`
      do
        if [ `grep -c "^${__v}=" $PREFIX/.env_start` -eq 1 ]; then
          __v0=`grep "^${__v}=" $PREFIX/.env_start | cut -f2 -d'='`
          __v1=`grep "^${__v}=" .env_current | cut -f2 -d'='`
          __v2=`echo "$__v1" | sed "s%$__v0%__DOLLAR__{${__v}}%g"`
          [ "X$__vv" != "X" ] && echo "export $__v=\"$__v2\"" >> .env_mod
        fi
      done
      if [ -f .env_mod ]; then
        sed -i "s%__DOLLAR__%\$%g" .env_mod
        cat <<EOF > my_make.sh
#!/bin/sh

PREFIX=$PREFIX
export PATH="\$PREFIX/.cargo/bin:\$PREFIX/bin:\$PATH"
export LD_LIBRARY_PATH="\$PREFIX/lib/x86_64-linux-gnu:\$PREFIX/lib64:\$PREFIX/lib"
export LD_PATH="\$PREFIX/lib/x86_64-linux-gnu:\$PREFIX/lib64:\$PREFIX/lib"
export PYTHONPATH=\$PREFIX/lib64/python${PYTHON_VER_MAJOR}.${PYTHON_VER_MINOR}/lib-dynload

make -j ${nthreads} && make install

EOF
        chmod +x my_make.sh
      fi
    fi
    touch .my_make_done1
  fi
  if [ ! -f .my_make_done ]; then
    printf " ### Coot: make (see `mypwd`/my_make.log) ... "
    make -j ${nthreads} > my_make.log 2>&1 || error "see `mypwd`/my_make.log"
    echo "done"
    printf " ### Coot: install (see `mypwd`/my_make_install.log) ... "
    make install > my_make_install.log 2>&1 || error "see `mypwd`/my_make_install.log"
    echo "done"

    touch .my_make_done
  fi
}

build_chapi () {
cat << EOF


########################################################################
### Building Chapi
########################################################################
EOF
  cd $COOT_BUILD_DIR
  # Do we need this here?
  additional_build_env_setup
  mkdir -p chapi-build && cd chapi-build || error
  # Todo: make sure we do it in a way consistent with how we build Coot (e.g. build type, build flags, etc.)
  if [ ! -f .my_cmake_done ]; then
    printf " ### Chapi: cmake (see `mypwd`/my_chapi_cmake.log) ... "
    cmake -S .. -DCMAKE_INSTALL_PREFIX=$PREFIX > my_chapi_cmake.log 2>&1 \
    || error "see `mypwd`/my_chapi_cmake.log"
    echo "done"
    touch .my_cmake_done
    rm -f .my_make_done
  fi
  if [ ! -f .my_make_done ]; then
    printf " ### Chapi: make (see `mypwd`/my_chapi_make.log) ... "
    make -j ${nthreads} > my_chapi_make.log 2>&1 || error "see `mypwd`/my_chapi_make.log"
    echo "done"
    touch .my_make_done
    do_cleans="`pwd` $do_cleans"
  fi
  if [ ! -f .my_install_done ]; then
    printf " ### Chapi: install (see `mypwd`/my_chapi_install.log) ... "
    make install > my_chapi_install.log 2>&1 || error "see `mypwd`/my_chapi_install.log"
    echo "done"
    touch .my_install_done
  fi

}

complete_coot () {
  # get reference structures:
  if [ ! -d $PREFIX/share/coot/reference-structures ]; then
    cd $PREFIX/share/coot || error
    do_wget https://www2.mrc-lmb.cam.ac.uk/personal/pemsley/coot/dependencies/reference-structures.tar.gz || error
    rm -f reference-structures.tar.gz || error
  fi

  # Full refmac/CCP4 monomer (geometry) library -- only for full tarballs (-fulltar).
  # Coot's "make install" already bundles a minimal (~115-monomer) set at
  # share/coot/lib/data/monomers; here we overlay the complete dictionary so chapi/Coot
  # has restraints for arbitrary ligands. The runtime COOT_REFMAC_LIB_DIR points at
  # share/coot/lib, i.e. Coot looks under <that>/data/monomers.
  #
  # The tarball's top dir is "monomers/", but that dir already exists (the bundled set),
  # so do_wget would skip unpacking it in place. We therefore unpack into a private temp
  # dir and merge its contents over the bundled set. Idempotency stamp lives in
  # $BUILD_DIR (not under share/) so it is not shipped in the tarball; we cannot guard on
  # mon_lib_list.cif because the bundled minimal set already provides that file.
  if [ $do_minimaltar -eq 0 ] && [ ! -f $BUILD_DIR/.my_full_monomers_done ]; then
    printf "\n ### fetching the full refmac monomer library (~36 MB) ...\n"
    mkdir -p $PREFIX/share/coot/lib/data/monomers || error
    __monomers_tmp=$PREFIX/share/coot/lib/.monomers_dl.$$
    rm -rf $__monomers_tmp
    mkdir -p $__monomers_tmp || error
    cd $__monomers_tmp || error
    do_wget https://www2.mrc-lmb.cam.ac.uk/personal/pemsley/coot/dependencies/refmac-monomer-library.tar.gz || error
    # do_wget unpacked ./monomers/ here; merge its contents over the bundled set
    # ("monomers/." copies the directory's contents, including any dotfiles)
    cp -a monomers/. $PREFIX/share/coot/lib/data/monomers/ || error
    cd $PREFIX/share/coot/lib || error
    rm -rf $__monomers_tmp || error
    touch $BUILD_DIR/.my_full_monomers_done || error
  fi
}

# Copy the symbolic icons the UI references out of Adwaita into share/coot/pixmaps, where they
# resolve as "unthemed" icons on the search path regardless of the host's active icon theme
# (the host forces its own theme, which our bundle-only XDG_DATA_DIRS lacks, so themed lookups
# would otherwise break). Scanning the .ui files keeps new -symbolic references covered.
bundle_themed_icons () {
  pixmaps=$PREFIX/share/coot/pixmaps
  adwaita_sym=$PREFIX/share/icons/Adwaita/symbolic
  { [ -d "$pixmaps" ] && [ -d "$adwaita_sym" ]; } || return 0
  copied=0
  names=`grep -rhoE 'icon-name">[^<]*-symbolic<' $PREFIX/share/coot/ui/*.ui 2>/dev/null \
           | sed -e 's%icon-name">%%' -e 's%<$%%' | sort -u`
  for n in $names
  do
    [ -e "$pixmaps/$n.svg" ] && continue          # already shipped as a Coot pixmap
    src=`find "$adwaita_sym" -name "$n.svg" -print 2>/dev/null | head -n 1`
    [ "X$src" != "X" ] || continue                # not in Adwaita (e.g. legacy, purged) -> skip
    cp -p "$src" "$pixmaps/$n.svg" && copied=`expr $copied + 1`
  done
  printf " ### bundled %s themed symbolic icon(s) into share/coot/pixmaps\n" "$copied"
}

create_readme () {
  [ -f README ] && readme="README.GPhL" || readme="README"
  cat <<EOF > $readme
##
## Automatic Coot build system version $my_version
##   Contact: buster-develop@globalphasing.com
##   Built = `date`
##

After unpacking the tarball in some directory DIR, just put the bin
directory onto your PATH, i.e.

  export PATH="DIR$1/bin:\$PATH"   # bash/sh/dash/zsh/ksh

or

  setenv PATH "DIR$1/bin:\$PATH"   # tcsh/csh

(replacing DIR with the correct directory name).

You can then run Coot and its tools, e.g.:

  coot
  findwaters --help

------------------------------------------------------------------------
Using the headless API (Chapi) from the bundled Python
------------------------------------------------------------------------

This build ships its own Python together with the "coot_headless_api"
module (a.k.a. Chapi). To use it, source the bundled environment file
once in your shell:

  . DIR$1/bin/coot-env.sh            # bash/sh/dash/zsh/ksh

then use the bundled python3, from any directory:

  python3 -c 'import coot_headless_api as chapi; print(chapi)'

coot-env.sh auto-detects the install location (override by setting
COOT_PREFIX) and exports PYTHONHOME, LD_LIBRARY_PATH and the COOT_* data
directories, so that "import coot_headless_api" just works.
EOF
}

package_coot_prep () {
  cd $PREFIX || error

  # Step 1: make installed bin/ scripts relocatable by replacing the absolute
  # build-time $PREFIX with the runtime `dirname $0`.
  printf "\n"
  # list bin/* scripts containing the literal $PREFIX path
  for script_file in `grep -l "$PREFIX" bin/* 2>/dev/null`
  do
    # `file` reports "...ELF..." for binaries -> leave them alone
    case `file $script_file` in
      *ELF*) continue;;
    esac
    printf " # change PREFIX in $script_file\n"
    # rewrite $PREFIX in its three contexts; "%" delimiter avoids escaping the "/"s
    #   \$ = $PREFIX at end of line;  $PREFIX/ = before a sub-path;  $PREFIX" = before a quote
    sed -i -e "s%$PREFIX\$%\`dirname \$0\`%g" \
           -e "s%$PREFIX/%\`dirname \$0\`/%g" \
           -e "s%$PREFIX\"%\`dirname \$0\`\"%g" \
           $script_file
  done

  # Step 2: make sure every Coot tool's real binary lives in libexec/. Coot installs
  # most of them there already (often as "<name>-bin"), but a few land directly in bin/
  # as plain ELF (e.g. coot-bfactan, coot-mmrrcc). Move any Coot-named ELF binary from
  # bin/ into libexec/ so step 3 can wrap it. "Coot tool" = name matching
  # coot*/layla*/mini-rsr* (this excludes GTK internals like gio*/at-spi*).
  for bin_path in bin/coot* bin/layla* bin/mini-rsr*
  do
    [ -f "$bin_path" ] || continue        # unmatched glob stays literal -> skip
    [ -L "$bin_path" ] && continue        # already a wrapper symlink -> skip
    case `file "$bin_path"` in *ELF*) ;; *) continue;; esac   # only real binaries
    tool=`basename "$bin_path"`
    if [ ! -e libexec/$tool ]; then
      printf " # move bin/$tool into libexec\n"
      mv "$bin_path" libexec/$tool || error
    fi
  done

  # Step 3: for each Coot-tool binary in libexec/, make bin/<name> a symlink to the
  # wrapper, where <name> is the libexec filename minus a trailing "-bin"
  # (layla-bin -> layla, coot-findwaters-bin -> coot-findwaters, coot-1 -> coot-1).
  # ln -sf overwrites Coot's own bin/ launcher in place (no shims, no .orig backups).
  wrapper_link_count=0
  for libexec_path in libexec/coot* libexec/layla* libexec/mini-rsr*
  do
    [ -f "$libexec_path" ] && [ -x "$libexec_path" ] || continue
    launcher=`basename "$libexec_path"`
    launcher=${launcher%-bin}
    ln -sf coot-wrapper.sh bin/$launcher && wrapper_link_count=`expr $wrapper_link_count + 1`
  done
  # friendly alias: bare "coot" is resolved to coot-1 by the wrapper
  ln -sf coot-wrapper.sh bin/coot && wrapper_link_count=`expr $wrapper_link_count + 1`

  printf "\n ### NOTE: created $wrapper_link_count bin -> coot-wrapper.sh symlinks\n"

}

make_font_dirs_and_files () {
  mkdir -p $PREFIX/etc/fonts/conf.d $PREFIX/share/fonts $PREFIX/var/cache/fontconfig
  cat <<EOF > $PREFIX/etc/fonts/fonts.conf
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>

  <!-- Where to find fonts -->
  <dir prefix="relative">../../share/fonts</dir>

  <!-- Cache directory -->
  <cachedir prefix="xdg">/fontconfig</cachedir>

  <!-- Include default rules -->
  <include ignore_missing="yes">conf.d</include>

</fontconfig>
EOF
  (
    cd $PREFIX/etc/fonts/conf.d && \
    ( 
      for __f in 10-hinting-slight.conf \
                 10-sub-pixel-rgb.conf \
                 11-lcdfilter-default.conf \
                 50-user.conf \
                 60-latin.conf \
                 65-nonlatin.conf \
                 70-no-bitmaps.conf \
                 80-delicious.conf \
                 90-synthetic.conf
      do
        [ ! -f $__f ] && [ -f ../../../share/fontconfig/conf.avail/$__f ] && ln -s ../../../share/fontconfig/conf.avail/$__f .
      done
    )
  )
  # ensure no abs-path links are lurking around
  (
    cd $PREFIX/etc/fonts/conf.d && \
    (
      for __f in `ls *.conf 2>/dev/null`
      do
        __t=`ls -l $__f | awk '{print $NF}'`
        [ "X$__f" = "X$__t" ] && continue
        case "$__t" in
          /*) rm $__f && cp -p "$__t" $__f;;
        esac
      done
    )
  )
  # enforce monospace (if requested):
  [ ! -f $PREFIX/etc/fonts/conf.d/50-force-monospace.conf ] && \
    cat <<EOF > $PREFIX/etc/fonts/conf.d/50-force-monospace.conf
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>

  <match target="pattern">
    <test name="family" compare="eq">
      <string>monospace</string>
    </test>
    <test name="spacing" compare="not_eq">
      <int>100</int>
    </test>
    <edit name="rejectfont">
      <bool>true</bool>
    </edit>
  </match>

</fontconfig>
EOF
  [ ! -f $PREFIX/etc/fonts/conf.d/49-monospace-stack.conf ] && \
    cat <<EOF > $PREFIX/etc/fonts/conf.d/49-monospace-stack.conf
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>

  <!-- Define a strict monospace preference chain -->
  <alias>
    <family>monospace</family>
    <prefer>
      <family>JetBrains Mono</family>
      <family>DejaVu Sans Mono</family>
      <family>Noto Sans Mono</family>
    </prefer>
  </alias>

  <!-- Hard reject proportional fonts for monospace requests -->
  <match target="font">
    <test name="family" compare="contains">
      <string>monospace</string>
    </test>
    <test name="spacing" compare="not_eq">
      <int>100</int>
    </test>
    <edit name="rejectfont">
      <bool>true</bool>
    </edit>
  </match>

</fontconfig>
EOF
  [ ! -f $PREFIX/etc/fonts/conf.d/60-monospace-symbols.conf ] && \
    cat <<EOF > $PREFIX/etc/fonts/conf.d/60-monospace-symbols.conf
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>

  <!-- Symbol fallback for monospace -->
  <match target="pattern">
    <test name="family" compare="contains">
      <string>monospace</string>
    </test>
    <edit name="family" mode="append">
      <string>Noto Sans Symbols</string>
      <string>Noto Sans Symbols 2</string>
      <string>Noto Color Emoji</string>
    </edit>
  </match>

</fontconfig>
EOF
}

# Echo a "<distro>-<version>" tag (for tarball names) from os-release / lsb-release.
# Returns 1 if the distro can't be determined, so callers can `|| return`.
detect_os_tag () {
  if [ -f /etc/os-release ]; then
    # sed "s/ [^-]*-/-/g": keep only NAME's first word, e.g. "Red Hat Enterprise Linux-9.5" -> "Red-9.5"
    (. /etc/os-release ; echo "$NAME-${VERSION_ID}" | sed "s/ [^-]*-/-/g")
  elif [ -f /etc/lsb-release ]; then
    (. /etc/lsb-release ; echo ${DISTRIB_ID}-${DISTRIB_RELEASE})
  else
    return 1
  fi
}

# Set $package_dirs to the install subdirs to ship, adding FontConfig (and rebuilding
# its cache) when present. Runs in the current directory, i.e. the $PREFIX install tree.
collect_package_dirs () {
  package_dirs="lib libexec share"
  [ -d lib64 ] && package_dirs="$package_dirs lib64"
  if [ -f bin/fc-match ]; then
    printf "  including FontConfig binaries, fonts and cache:\n"
    [ -d var/cache/fontconfig ] && package_dirs="$package_dirs var/cache/fontconfig"
    package_dirs="$package_dirs etc"
    make_font_dirs_and_files
    (
      FONTCONFIG_PATH="$PREFIX/etc/fonts"
      FONTCONFIG_FILE="$PREFIX/etc/fonts/fonts.conf"
      FONTCONFIG_CACHE="$PREFIX/var/cache/fontconfig"
      XDG_CACHE_HOME="$PREFIX/var/cache"
      LD_LIBRARY_PATH="$PREFIX/lib64:$PREFIX/lib"
      PATH=$PREFIX/bin:$PATH
      export FONTCONFIG_PATH FONTCONFIG_FILE FONTCONFIG_CACHE XDG_CACHE_HOME LD_LIBRARY_PATH PATH
      unset FONTCONFIG_SYSROOT
      # indent each fc-cache line 5 spaces (was awk), drop the " skipping"/" 0 fonts" noise (| = OR)
      fc-cache -rv 2>&1 | sed 's/^/     /' | grep -E -v " skipping| 0 fonts"
    )
  fi
}

# bin/ tools we deliberately drop from the tarball: build-time only (toolchain + codegen/
# introspection). Everything else in bin/ ships — blocklist, not whitelist, so runtime
# helpers Coot/glycin exec (e.g. bwrap) are never silently lost.
bin_exclude="cmake ctest cpack ccmake cmake-gui ninja meson swig ccache pkg-config pkgconf
glib-compile-resources glib-compile-schemas glib-genmarshal glib-gettextize glib-mkenums gtester gtester-report gdbus-codegen
g-ir-scanner g-ir-compiler g-ir-generate g-ir-inspect g-ir-doc-tool
gdk-pixbuf-csource gdk-pixbuf-pixdata gdk-pixbuf-query-loaders
gtk4-builder-tool gtk4-encode-symbolic-svg gtk4-path-tool gtk4-rendernode-tool gtk4-image-tool
wayland-scanner update-mime-database eu-*"

package_coot () {
  cd $PREFIX || error
  os=`detect_os_tag` || return
  case $btype in
    debug) build_label=debug;;
    *) build_label=release;;
  esac
  tarball_name=coot_${os}_`uname -m`_${build_label}_`date +%Y%m%d_%H%M%S`.tar.zst
  collect_package_dirs
  create_readme
  printf "\n packaging Coot as $tarball_name ... "
  # ship all of bin/ minus $bin_exclude (build tools). zstd -19 (-T0 = all cores).
  __bin_excl=""; for __x in $bin_exclude; do __bin_excl="$__bin_excl --exclude=bin/$__x"; done
  tar -I 'zstd -T0 -19' -cf $tarball_name $__bin_excl bin $package_dirs > my_tar.log 2>&1 || error "see `mypwd`/my_tar.log"
  echo "done"
  printf "\n   "
  ls -l $tarball_name
  printf "\n"
}
package_coot_minimal () {
  cd $PREFIX || error
  os=`detect_os_tag` || return
  case $btype in
    debug) build_label=debug;;
    *) build_label=release;;
  esac
  package_basename=coot-${outtag}-minimal_${os}_`uname -m`_${build_label}_`date +%Y%m%d_%H%M%S`
  tarball_name=$package_basename.tar.zst
  collect_package_dirs
  # stage a throwaway copy under a PID-named temp dir ($$ = this shell's PID), so we
  # can prune and strip it without touching the real install
  staging_root="__$$.tmp"
  staging_dir="$staging_root/$package_basename"
  mkdir -p $staging_dir || error
  # Copy via tar (not cp) to preserve nested paths: $package_dirs can contain
  # "var/cache/fontconfig", which `cp -ar dest/.` would flatten to dest/fontconfig.
  ( tar -cf - $package_dirs | ( cd $staging_dir && tar -xf - ) ) || error "copy-1 (see above)"
  # ship all of bin/, then drop the build-time tools ($bin_exclude) — blocklist, not whitelist
  mkdir -p $staging_dir/bin
  cp -a bin/. $staging_dir/bin/ || error "copy-2 (see above)"
  for __x in $bin_exclude; do rm -f $staging_dir/bin/$__x; done
  (
    cd $staging_dir || error

    printf "\n preparing for minimal size ...\n"
    printf "   removing static libraries and intermediates (*.a, *.i) ...\n"
    find . -type f -name "*.[ai]" | xargs -r rm        # [ai] = a or i
    printf "   removing libtool archives (*.la) ...\n"
    find . -type f -name "*.la" | xargs -r rm
    printf "   removing non-English locales ...\n"
    find share/locale -type d ! -name en | xargs -r rm -fr
    printf "   removing stray HTML docs (keeping Coot's own) ...\n"
    find share -type f -name "*html" | grep -v coot | xargs -r rm   # grep -v coot = exclude Coot's docs
    rm -fr share/man share/doc share/RDKit/Docs share/cmake*/Help share/cmake*/Modules   # docs/help trees
    # strip symbols to shrink libraries/binaries, when `strip` is available — but never
    # for a debug build, where stripping would throw away the very symbols it's built for.
    if [ "$btype" != "debug" ] && type strip >/dev/null 2>&1; then
      printf "   stripping shared libraries ...\n"
      # .so files and versioned .so.N: name ends in "so" or in a digit ($ = end; | = OR)
      find lib* -name "*.so*" -type f | grep -E "so$|[0-9]$" | xargs -r -n 1 strip
      printf "   stripping libexec binaries ...\n"
      find libexec -type f ! -name "*.*" | xargs -r -n 1 strip          # ! -name "*.*" = no dot in name
      printf "   stripping bin binaries ...\n"
      find bin -type f -size +100k ! -name "*.*" | xargs -r -n 1 strip  # >100k, no extension
    fi
    echo "done"

    create_readme /$package_basename
    cd ../ || error
    # now inside $staging_root; "*" is just the $package_basename dir; write tarball + log one level up
    printf "\n packaging minimal Coot as $tarball_name ... "
    # zstd -19 (-T0 = all cores) for a much smaller tarball than gzip; needs the zstd CLI.
    tar -I 'zstd -T0 -19' -cf ../$tarball_name * > ../my_tar.log 2>&1 || error "see `dirname $PWD`/my_tar.log"
    echo "done"
  )
  rm -fr $staging_root || error
  printf "\n"
  ls -l $tarball_name
  printf "\n"
}

# download_all — the whole download phase: every toolchain + dependency source, fetched
# up front (before anything is built). Deliberately does NOT download Coot itself.
download_all () {
  download_toolchain    || error
  download_dependencies || error
}
create_coot_wrapper () {
  cd $PREFIX || error
  if [ ! -f bin/coot-wrapper.sh ]; then
    cat <<'EOF' > bin/coot-wrapper.sh
#!/bin/sh
# -*-shell-script-*-
# coot-wrapper.sh — generic launcher for the relocatable Coot install.
# Every bin/<tool> is a symlink to this script. It locates the install, sources the
# shared environment (coot-env.sh), then resolves and execs the real libexec binary.
# Copyright 2004-2007 University of York; reworked by GPhL.

# --- locate ourselves ---
#   invoked_name = how we were called (basename of $0): coot, layla, coot-findwaters ...
#   root_dir     = install prefix (our dir with a trailing /bin removed)
case "$0" in
  /*) self_path="$0";;
  *) self_path="`pwd`/$0";;
esac
invoked_name=`basename "$self_path"`
root_dir=`dirname "$self_path"`
case "$root_dir" in
  */bin) root_dir=`dirname "$root_dir"`;;
esac

# --- utility helpers ---
error () {
  [ "X$@" != "X" ] && printf "\n ERROR: $@\n\n" || printf "\n ERROR: see above\n\n"
  exit 1
}
warning () {
  [ "X$@" != "X" ] && printf "\n WARNING: $@\n\n" || printf "\n WARNING: see above\n\n"
}
usage () {
  printf "\n USAGE: $invoked_name [-h] [-v] [--ldd|--debug|--strace] ...\n\n"
}

# --- environment: single source of truth, shared with interactive `. coot-env.sh` use.
#     Pass our own prefix in so coot-env.sh need not re-derive it. ---
COOT_PREFIX="$root_dir"; export COOT_PREFIX
if [ -r "$root_dir/bin/coot-env.sh" ]; then
  . "$root_dir/bin/coot-env.sh"
else
  warning "coot-env.sh not found in $root_dir/bin - environment may be incomplete"
fi

# --- launch-only locale (kept here, NOT in coot-env.sh, so sourcing that file does not
#     clobber an interactive user's locale) ---
LANG=C LC_ALL=C LC_NUMERIC=C
export LANG LC_ALL LC_NUMERIC

# --- parse wrapper-only flags; everything else passes through to the real binary ---
do_ldd=0; do_debug=0; do_strace=0; iverb=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h) usage; exit 0;;
    --ldd) do_ldd=1; shift;;
    --debug) do_debug=1; shift;;
    --strace) do_strace=1; shift;;
    -v) iverb=`expr $iverb + 1`; shift;;
    *) break;;
  esac
done

# --- resolve the real binary: libexec/<name>, then libexec/<name>-bin, then the sole
#     alias (bare "coot" -> the versioned coot-1) ---
target_exe=
for candidate in "$root_dir/libexec/$invoked_name" "$root_dir/libexec/$invoked_name-bin"; do
  [ -x "$candidate" ] && target_exe="$candidate" && break
done
[ "X$target_exe" = "X" ] && [ "$invoked_name" = coot ] && [ -x "$root_dir/libexec/coot-1" ] \
  && target_exe="$root_dir/libexec/coot-1"
[ "X$target_exe" = "X" ] && error "no libexec binary found for \"$invoked_name\""

# --- env self-check: warn only, never abort (a slightly incomplete install should still
#     try to run; Coot reports its own errors) ---
[ "X$COOT_PREFIX" = "X" ]     && warning "COOT_PREFIX is not set"
[ "X$LD_LIBRARY_PATH" = "X" ] && warning "LD_LIBRARY_PATH is not set"
[ -d "$COOT_DATA_DIR" ]       || warning "Coot data dir not found: $COOT_DATA_DIR"

[ $iverb -gt 0 ] && printf "\n invoked=%s\n root=%s\n target=%s\n\n" "$invoked_name" "$root_dir" "$target_exe"

# --- run ---
if [ $do_ldd -eq 1 ]; then
  ldd "$target_exe"
elif [ $do_strace -eq 1 ]; then
  type strace >/dev/null 2>&1 || error "no \"strace\" command found"
  strace "$target_exe" "$@"
elif [ $do_debug -eq 1 ]; then
  printf "\n ### Running: \"%s\" %s\n\n" "$target_exe" "$*"
  fc-match -v monospace 2>/dev/null | grep file
  fc-match -v serif 2>/dev/null | grep file
  fc-match -v sans 2>/dev/null | grep file
  "$target_exe" "$@" || error
else
  # rewrite the program's own "Usage: <prog>" line to show the name actually invoked
  "$target_exe" "$@" 2>&1 | sed "s%Usage:[ ]*[^ ]*%Usage: $invoked_name%g" || error
fi
exit 0
EOF
    chmod +x bin/coot-wrapper.sh
  fi
}

# Emit bin/coot-env.sh: a *sourceable* env file so users can drive the bundled Python
# (e.g. `python3 -c 'import coot_headless_api'`) from their own shell. Named coot-env.sh
# so it is picked up by the "bin/coot*" glob in package_coot{,_minimal}. Written via a
# single-quoted heredoc so it self-derives the prefix at runtime (stays relocatable).
create_coot_env () {
  cd $PREFIX || error
  if [ ! -f bin/coot-env.sh ]; then
    cat <<'EOF' > bin/coot-env.sh
#!/bin/sh
# coot-env.sh — source this to use the tarball-shipped Coot and its bundled Python
# from your own shell. After sourcing, the shipped python3 can import the headless
# API:   python3 -c 'import coot_headless_api'
#
# Usage (sh/bash/zsh/ksh):
#     . /path/to/coot/bin/coot-env.sh
#
# The install location is auto-detected; override by setting COOT_PREFIX beforehand.

# --- locate the install prefix (the dir above this script's bin/) ---
if [ "X${COOT_PREFIX:-}" = "X" ]; then
  # this file is *sourced*, so $0 is unreliable; find our own path per shell
  if [ -n "${BASH_SOURCE:-}" ]; then
    _coot_self=${BASH_SOURCE}            # bash
  elif [ -n "${ZSH_VERSION:-}" ]; then
    _coot_self=${(%):-%x}                # zsh: %x = path of the sourced file
  else
    _coot_self=$0                        # other shells: best effort
  fi
  _coot_bindir=$(cd "$(dirname "$_coot_self")" && pwd)
  COOT_PREFIX=$(dirname "$_coot_bindir") # bin/ -> install root
  unset _coot_self _coot_bindir
fi

if [ ! -d "$COOT_PREFIX/lib" ]; then
  echo "coot-env.sh: COOT_PREFIX=\"$COOT_PREFIX\" does not look like a Coot install" >&2
  echo "  (set COOT_PREFIX to the unpacked tarball root and re-source)" >&2
  return 1 2>/dev/null || exit 1
fi
export COOT_PREFIX

PATH="$COOT_PREFIX/bin:$PATH"; export PATH

# --- shared libraries: prepend whichever lib dirs exist under the prefix ---
# Each "${VAR:+:$VAR}" appends the caller's existing value only when it is non-empty,
# avoiding a dangling ":" (an empty entry = current dir ".", a correctness/security trap).
_coot_ld=
for _coot_d in lib64 lib lib/x86_64-linux-gnu; do
  [ -d "$COOT_PREFIX/$_coot_d" ] && _coot_ld="${_coot_ld:+$_coot_ld:}$COOT_PREFIX/$_coot_d"
done
LD_LIBRARY_PATH="${_coot_ld}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"; export LD_LIBRARY_PATH
unset _coot_ld _coot_d

# PYTHONHOME makes the shipped python3 find its stdlib + site-packages (where
# coot_headless_api lives); no PYTHONPATH needed.
PYTHONHOME="$COOT_PREFIX"; export PYTHONHOME

# --- GObject-introspection typelibs (GTK) ---
_coot_gi=
for _coot_d in lib/girepository-1.0 lib64/girepository-1.0 lib/x86_64-linux-gnu/girepository-1.0; do
  [ -d "$COOT_PREFIX/$_coot_d" ] && _coot_gi="${_coot_gi:+$_coot_gi:}$COOT_PREFIX/$_coot_d"
done
[ -n "$_coot_gi" ] && { GI_TYPELIB_PATH="${_coot_gi}${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"; export GI_TYPELIB_PATH; }
unset _coot_gi _coot_d

# --- Coot data directories / files (so Coot + chapi find dictionaries/structures) ---
COOT_DATA_DIR="$COOT_PREFIX/share/coot"; export COOT_DATA_DIR
[ -d "$COOT_PREFIX/share/coot/scheme" ]                && { COOT_SCHEME_DIR="$COOT_PREFIX/share/coot/scheme"; export COOT_SCHEME_DIR; }
[ -f "$COOT_PREFIX/share/coot/standard-residues.pdb" ] && { COOT_STANDARD_RESIDUES="$COOT_PREFIX/share/coot/standard-residues.pdb"; export COOT_STANDARD_RESIDUES; }
[ -f "$COOT_PREFIX/share/coot/syminfo.lib" ]           && { SYMINFO="$COOT_PREFIX/share/coot/syminfo.lib"; export SYMINFO; }
[ -f "$COOT_PREFIX/share/coot/cootrc" ]                && { COOT_RESOURCES_FILE="$COOT_PREFIX/share/coot/cootrc"; export COOT_RESOURCES_FILE; }
[ -d "$COOT_PREFIX/share/coot/reference-structures" ]  && { COOT_REF_STRUCTS="$COOT_PREFIX/share/coot/reference-structures"; export COOT_REF_STRUCTS; }
# monomer/dictionary library (only when the user hasn't pointed at a CCP4 one via CLIBD_MON)
[ "X${CLIBD_MON:-}" = "X" ] && [ -d "$COOT_PREFIX/share/coot/lib" ] && { COOT_REFMAC_LIB_DIR="$COOT_PREFIX/share/coot/lib"; export COOT_REFMAC_LIB_DIR; }

# --- Guile (Coot's scheme scripting) ---
GUILE_WARN_DEPRECATED=no; export GUILE_WARN_DEPRECATED
[ -d "$COOT_PREFIX/share/guile/3.0" ] && { GUILE_LOAD_PATH="$COOT_PREFIX/share/guile/3.0"; export GUILE_LOAD_PATH; }

# --- XDG + bundled FontConfig (use Coot's own fonts/cache, not the host's). Each is
# skipped if the matching COOT_* override is set, so the user can keep their own. ---
[ -d "$COOT_PREFIX/share" ]                && [ "X${COOT_XDG_DATA_DIRS:-}" = "X" ]   && { XDG_DATA_DIRS="$COOT_PREFIX/share"; export XDG_DATA_DIRS; }
[ -d "$COOT_PREFIX/var/cache" ]            && [ "X${COOT_XDG_CACHE_HOME:-}" = "X" ]  && { XDG_CACHE_HOME="$COOT_PREFIX/var/cache"; export XDG_CACHE_HOME; }
[ -d "$COOT_PREFIX/etc/fonts" ]            && [ "X${COOT_FONTCONFIG_PATH:-}" = "X" ] && { FONTCONFIG_PATH="$COOT_PREFIX/etc/fonts"; export FONTCONFIG_PATH; }
[ -f "$COOT_PREFIX/etc/fonts/fonts.conf" ] && [ "X${COOT_FONTCONFIG_FILE:-}" = "X" ] && { FONTCONFIG_FILE="$COOT_PREFIX/etc/fonts/fonts.conf"; export FONTCONFIG_FILE; }
[ -d "$COOT_PREFIX/var/cache/fontconfig" ] && [ "X${COOT_FC_CACHEDIR:-}" = "X" ]     && { FC_CACHEDIR="$COOT_PREFIX/var/cache/fontconfig"; export FC_CACHEDIR; }

# --- TLS CA certificates: the bundled OpenSSL ships no cert store, so point it at the
# host's CA bundle (desktop Linux is expected to provide one). All skipped if already set. ---
if [ "X${SSL_CERT_FILE:-}" = "X" ]; then
  for _coot_ca in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt \
                  /etc/ssl/ca-bundle.pem /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem \
                  /etc/ssl/cert.pem; do
    [ -f "$_coot_ca" ] && { SSL_CERT_FILE="$_coot_ca"; export SSL_CERT_FILE; break; }
  done
  unset _coot_ca
fi
[ "X${SSL_CERT_DIR:-}" = "X" ] && [ -d /etc/ssl/certs ] && { SSL_CERT_DIR=/etc/ssl/certs; export SSL_CERT_DIR; }
[ "X${CURL_CA_BUNDLE:-}" = "X" ] && [ -n "${SSL_CERT_FILE:-}" ] && { CURL_CA_BUNDLE="$SSL_CERT_FILE"; export CURL_CA_BUNDLE; }

# Return success: the trailing conditionals above leave $? non-zero when their dirs are
# absent, which would abort a caller that sources this file under `set -e`.
:
EOF
    chmod +x bin/coot-env.sh
  fi
}

# -------------------------------------------------------------------------------------
# Phase dispatch. The build is divided into four ordered phases; $stage selects which to
# run ("all" = the whole thing, the default; a -*-only flag narrows it to one). The
# split lets Coot's CI build+cache the dependency stack (download/toolchain/deps) without
# Coot, then build Coot alone against the restored cache (-coot-stage-only).
# setup_build_env runs first regardless: every phase needs its env vars + $PREFIX/bin.
# -------------------------------------------------------------------------------------
setup_build_env || error

case $stage in all|download)
  printf "\n##################### download (sources) ##################### \n\n"
  download_all || error
  ;;
esac

case $stage in all|toolchain)
  printf "\n###################### toolchain build ###################### \n\n"
  initial_setup || error
  ;;
esac

case $stage in all|deps)
  printf "\n#################### dependency build ###################### \n\n"
  build_dependencies || error
  ;;
esac

case $stage in all|coot)
  cat <<e

########################################################################
### Now for the real thing: Coot
########################################################################

e
  download_coot || error
  build_coot    || error
  if [ $no_chapi -eq 0 ]; then
    build_chapi || error
  fi
  complete_coot || error
  printf "\n################### bundling themed icons #################### \n\n"
  bundle_themed_icons || error
  printf "\n####################### handling fonts ####################### \n\n"
  extract_fonts || error
  printf "\n###################### package_coot_prep ##################### \n\n"
  package_coot_prep        || error
  printf "\n#################### create_coot_wrapper ##################### \n\n"
  create_coot_wrapper      || error
  printf "\n###################### create_coot_env ###################### \n\n"
  create_coot_env          || error
  if [ $do_minimaltar -eq 1 ]; then
    printf "\n#################### package_coot_minimal #################### \n\n"
    package_coot_minimal   || error
  else
    printf "\n######################## package_coot ######################## \n\n"
    package_coot           || error
  fi
  ;;
esac

cat <<EOF

########################################################################

  To save space you could now do

    find build -type d -name .libs | xargs rm -fr
    find build -type d -name .deps | xargs rm -fr

  or just

    rm -fr coot deps build .cargo .rustup

  (to use the installation here) or even

    rm -fr coot deps build .cargo .rustup doc etc info var libexec bin include share lib lib64

  and use the created tarball (after unpacking) instead.

########################################################################

EOF

if [ $do_clean -eq 1 ]; then
  for d in $do_cleans
  do
    ( cd $d && ( ( [ -f Makefile ] || [ -f GNUmakefile ] ) && make clean > my_make_clean.log 2>&1 ) )
  done
fi

exit 0
