#!/bin/sh

my_version=1.0
#url_contrib="https://cloud.globalphasing.org/s/jC8RHNBfzmoxfL7"
url_contrib="https://cloud.globalphasing.org/public.php/dav/files/jC8RHNBfzmoxfL7/"

# -------------------------------------------------------------------------------------
# This script is meant to be run interactively: all download, building
# and installation is done in current directory

mypwd () {
  [ "X$PREFIX" != "X" ] && [ -d "$PREFIX" ] && pwd | sed "s%^${PREFIX%/}/%%g" || pwd
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
usage () {
  printf "\n USAGE: `basename $0` [-h] [-v] [-nthreads <N>] [-fulltar] [-distro] [-depplus]\n"
  printf "\n  -h                     : this help message\n"
  printf "\n  -v                     : increase verbosity\n"
  printf "\n  -nthreads <N>          : set number of threads to use (where possible); default = use all\n"
  printf "\n  -fulltar               : create \"full\" tarball at the end (including various static libs, docs etc)\n"
  printf "\n  -distro                : build binaries for distribution (default is to tune for local machine/CPU)\n"
  printf "\n  -depplus               : try and build more external dependencies (that are usually provided by OS at runtime)\n"
  printf "\n  -os                    : also install OS-provided packages deemed necessary (if possible)\n"
  printf "\n  -noninteractive        : do not interactively ask for confirmation\n"
  printf "\n  -tag <tag>             : Coot tag (for specific release; default = \"$COOT_TAG\")\n"
  printf "\n  -branch <branch>       : Coot branch (default = \"$COOT_BRANCH\")\n"
  printf "\n  -patch <file>          : Coot patch file\n"

  printf "\n Tested on:\n"
  printf "   AlmaLinux 8.10 and 9.5 (todo: test again)\n"
  printf "   Arch Linux (20260402)\n"
  printf "   Debian 13\n"
  printf "   Fedora Linux 43 and 44\n"
  printf "   openSUSE Leap 15 (todo: test again)\n"
  printf "   Rocky Linux 9.7\n"
  printf "   Ubuntu 24.04 and 26.04\n"
}

case `uname` in
  Linux) true;;
  *) error "running on a non-Linux system!";;
esac

# save current environment
env | sort > .env_start || error
umask 022

## -------------------------------------------------------------------------------
## Command-line arguments
## -------------------------------------------------------------------------------
iverb=0
nthreads=`nproc --all`
do_minimaltar=1
do_distro=0
do_noninteractive=0
do_depplus=0
do_os=0
tag=""
branch=""
COOT_TAG="main"
COOT_BRANCH=""
patch_file=""
btype="opt"
do_wgotten=0
do_clean=0
while [ $# -gt 0 ]
do
   case $1 in
    -h|-help|--help)usage;exit 0;;
    -v)iverb=`expr $iverb + 1`;;
    -nthreads)nthreads=$2;shift;;
    -minimaltar)do_minimaltar=1;;
    -fulltar)do_minimaltar=0;;
    -distr*)do_distro=1;;
    -clean*) do_clean=1;;
    -depplus*) do_depplus=1;;
    -[oO][sS]) do_os=1;;
    -noninteractive) do_noninteractive=1;;
    -tag) tag=$2;outtag=${tag#Release-};shift;;
    -branch) branch=$2;outtag=$branch;shift;;
    -debug) btype="debug";;
    -wgotten)do_wgotten=1;;
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
      # probably not all needed:
      $sudo zypper install -y \
            -t pattern devel_basis || error
      # probably not all needed:
      $sudo zypper install -y \
             openssl-devel \
             wget \
             git \
             vim \
             gzip \
             hostname \
             gcc13 \
             gcc13-fortran \
             gcc13-c++ \
             autoconf \
             automake \
             blas-devel \
             fftw-devel \
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
             libXrandr-devel \
             libXi-devel \
             libXcursor-devel \
             libXinerama-devel \
             libXdamage-devel \
             libexpat-devel \
             dbus-1-devel \
             libmount-devel \
             libffi-devel \
             libelf-devel \
             readline-devel \
             ncurses-devel \
             lzo-devel \
             libbz2-devel \
             libpng16-devel \
             libbrotli-devel \
             libxcb-devel \
             xcb-util-devel \
             xcb-util-renderutil-devel \
             libX11-devel \
             libXrender-devel \
             libXext-devel \
             libxkbcommon-devel \
             gmp-devel \
             libglfw-devel \
             xmlto \
             docbook_4 \
             docbook-xsl-stylesheets \
             bc \
             gperf \
             gettext-tools \
             libpsl-devel \
             || error
      ;;
    rocky*|alma*|centos*)
        $sudo dnf update -y
        $sudo dnf install -y dnf-plugins-core
        $sudo dnf config-manager --set-enabled crb
        $sudo dnf install -y epel-release
        $sudo dnf config-manager --set-enabled powertools
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
            $__toolsets \
            bzip2-devel \
            gperf \
            libX11-devel \
            libglvnd-devel \
            libffi-devel \
            freetype-devel \
            libxkbcommon-devel \
            libXrender-devel \
            libXext-devel \
            libXrandr-devel \
            libXi-devel \
            libXcursor-devel \
            libXdamage-devel \
            libXinerama-devel \
            libdrm-devel \
            blas-devel \
            tar \
            openssl-devel \
            bison \
            libxml2-devel \
            bzip2 \
            autoconf \
            automake \
            libtool \
            git \
            flex \
            gperftools-devel \
            expat-devel \
            dbus-devel \
            libmount-devel \
            elfutils-libelf-devel \
            readline-devel \
            ncurses-devel \
            sqlite-devel \
            lzo-devel \
            libpng-devel \
            brotli-devel \
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
            libpsl-devel \
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
          fedora-4[5-9]) __toolsets="gcc15 gcc15-gfortran gcc15-c++";yum="dnf install --skip-unavailable -y";; # probably won't work
          *) __toolsets="gcc14 gcc14-gfortran gcc14-c++";yum="yum install -y";;
        esac
        $sudo $yum \
              gcc \
              wget \
              vim \
              hostname \
              gcc-c++ \
              gcc-gfortran \
              bzip2-devel \
              libX11-devel \
              libglvnd-devel \
              libffi-devel \
              freetype-devel \
              libxkbcommon-devel \
              libXrender-devel \
              libXext-devel \
              libXrandr-devel \
              libXi-devel \
              libXcursor-devel \
              tar \
              openssl-devel \
              bison \
              libXdamage-devel \
              libXinerama-devel \
              libdrm-devel \
              expat-devel \
              libxml2-devel \
              bzip2 \
              autoconf \
              automake \
              libtool \
              git \
              flex \
              gperf \
              gperftools-devel \
              $__toolsets \
              blas-devel \
              dbus-devel \
              libmount-devel \
              elfutils-libelf-devel \
              readline-devel \
              ncurses-devel \
              sqlite-devel \
              lzo-devel \
              libpng-devel \
              brotli-devel \
              libxcb-devel \
              xcb-util-devel \
              gmp-devel \
              glfw-devel \
              bc \
              gettext \
              make \
              xmlto \
              pkgconf-pkg-config \
              libpsl-devel
        case `echo "$os" | tr '[A-Z]' '[a-z]'` in
          fedora-4[2-9]) dnf builddep -y python3-gobject-devel;;
        esac
      ;;
    debian*|ubuntu*)
        $sudo apt-get update || error
        $sudo apt-get -y install \
          git wget build-essential gfortran gettext pkg-config bison flex make automake gperf vim xmlto libtool-bin \
          libdbus-1-dev libmount-dev libexpat1-dev libffi-dev libelf-dev libxml2-dev libxml2-utils libreadline-dev \
          libssl-dev libncurses-dev libsqlite3-dev liblzo2-dev libbz2-dev libpng-dev libbrotli-dev \
          libxcb-glx0-dev \
          libegl1-mesa-dev \
          libxrender-dev libxcb-render0-dev libxcb-render-util0-dev libxext-dev libxrandr-dev libxi-dev libxcursor-dev \
          libxdamage-dev libxinerama-dev \
          libxkbcommon-x11-dev libxcb-shm0-dev libxcb-util-dev libxcb1-dev libx11-dev libxcb-dri3-dev libx11-xcb-dev \
          libopenblas-dev libgmp-dev libgc-dev libunistring-dev libpcre2-dev libdrm-dev libglm-dev \
          libglfw3-dev \
          libpsl-dev \
          xz-utils \
          bc || error
      ;;
    arch*)
      $sudo pacman -Syu --needed --noconfirm \
            base-devel git wget gcc-fortran gperf vim xmlto docbook-xml docbook-xsl cmake \
            dbus util-linux-libs expat libffi elfutils libxml2 readline \
            openssl ncurses sqlite lzo xz bzip2 libpng brotli \
            libxcb \
            mesa \
            libxrender xcb-util-renderutil libxext libxrandr libxi libxcursor \
            libxdamage libxinerama \
            libxkbcommon xcb-util libx11 \
            openblas blas gmp gc libunistring pcre2 libdrm glm \
            glfw \
            inetutils libpsl bc || error
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

# is that reliable?
if [ "X$COOT_TAG$COOT_BRANCH" != "X" ]; then
  case "$COOT_TAG$COOT_BRANCH" in
    *0.9.*|*refinement*) COOT_VER=0.9;;
    *)COOT_VER=1;;
  esac
else
  COOT_VER=1
fi

if [ "X$BUILD_DEPENDENCIES" = "X" ]; then
  case $COOT_VER in
    1) [ $do_depplus -eq 1 ] && BUILD_DEPENDENCIES_PLUS="
             expat
             libvdpau
             libdrm
             wayland
             xkbcommon
             xcbproto
             xproto
             xf86vidmodeproto
             xextproto
             libxcb
             libxshmfence
             libxxf86vm
             libxext
             glproto
             dri2proto
             elfutils
             mesaglu
             mesa
             freeglut
             "
         # order matters - and some have to be done multiple times it seems
         BUILD_DEPENDENCIES="
           pcre2
           glib
           gobject_introspection
           libunistring
           gc
           glm
           # This is needed before Python and should be obtained as a system-level dependency.
           # Todo: remove it here
           libffi
           $BUILD_DEPENDENCIES_PLUS
           guile
           swig
           libepoxy
           boost
           glib
           graphene
           harfbuzz
           freetype
           fontconfig
           libjpeg
           pixman
           cairo
           harfbuzz
           pango
           smi
           gdk_pixbuf
           librsvg
           tiff
           curl
           poppler
           cairo
           gdk_pixbuf
           atk
           wayland
           gtk
           pygobject 
           fftw
           rdkit
           mmdb2
           gsl
           gemmi
           libccp4
           libssm
           libclipper"
           ;;
    0.9) [ $do_depplus -eq 1 ] && BUILD_DEPENDENCIES_PLUS=""
         # order matters - and some have to be done multiple times it seems
         BUILD_DEPENDENCIES="
           libccp4
           mmdb2
           libssm
           fftw
           libclipper
           freeglut
           gtkglext
           libart
           libgnomecanvas
           goocanvas
           # This is needed before Python and should be obtained as a system-level dependency.
           # Todo: remove it from here
           readline
           pygobject
           pygtk
           boost
           numpy
           pillow
           rdkit
           biscuit
           gmp
           libtool
           guile
           greg
           guilegtk
           guilegui
           guilelib
           libidn
           curl
           clustalw
           libgd
           raster3d"
         ;;
    esac
fi
# -------------------------------------------------------------------------------------

# versions of all external packages/dependencies:
case `echo "$os" | tr '[A-Z]' '[a-z]'` in
  opensuse*)
    CMAKE_VER=3.31.11
  ;;
  *)
    CMAKE_VER=4.3.1
  ;;
esac
NINJA_VER=1.13.2

case $COOT_VER in
  1)   PYTHON_VER_MAJOR=3
       PYTHON_VER_MINOR=14
       PYTHON_VER_PATCH=3

       BOOST_VER=1.89.0
       PYGOBJECT_VER=3.54.5
       FREEGLUT_VER=3.8.0
       RDKIT_VER=2025_09_6
       NUMPY_VER=2.4.3

       ;;
  0.9) PYTHON_VER_MAJOR=2
       PYTHON_VER_MINOR=7
       PYTHON_VER_PATCH=18

       BOOST_VER=1.72.0
       PYGOBJECT_VER=2.8.0
       FREEGLUT_VER=2.4.0
       RDKIT_VER=2018_09_3
       NUMPY_VER=1.16.6

       PILLOW_VER=6.2.2
       PYGTK_VER=2.6.3
       READLINE_VER=6.3
       GOOCANVAS_VER=1.0.0
       LIBGNOMECANVAS_VER=2.30.3
       LIBART_VER=2.3.21
       GTKGLEXT_VER=1.20
       ;;
esac
PYTHON_VER="${PYTHON_VER_MAJOR}.${PYTHON_VER_MINOR}.${PYTHON_VER_PATCH}"

LIBJPEG_VER=3.1.3
GLIB_VER=2.86.4
GOBJECT_INTROSPECTION_VER_MM=1.86
GOBJECT_INTROSPECTION_VER=${GOBJECT_INTROSPECTION_VER_MM}.0
GUILE_VER=3.0.11
SWIG_VER=4.4.0
LIBEPOXY_VER=1.5.10
GRAPHENE_VER=1.10.8
HARFBUZZ_VER=13.2.1
FREETYPE_VER=2.14.3
FONTCONFIG_VER=2.17.1
FONTS_INTER_VER=4.1
FONTS_JETBRAINS_VER=2.304
FONTS_DEJAVU_VER=2.37
PIXMAN_VER=0.46.4
LIBTIFF_VER=4.7.1
POPPLER_VER=26.03.0
CURL_VER=8.19.0
CAIRO_VER=1.18.4
PANGO_VER_MM=1.57
PANGO_VER=${PANGO_VER_MM}.1
SMI_VER=2.4
# Todo: fix build - broken autogen stuff
# LIBRSVG_VER_MM=2.61
# LIBRSVG_VER=${LIBRSVG_VER_MM}.4
LIBRSVG_VER_MM=2.58
LIBRSVG_VER=${LIBRSVG_VER_MM}.0
GDK_PIXBUF_VER_MM=2.44
GDK_PIXBUF_VER=${GDK_PIXBUF_VER_MM}.4
ATK_VER_MM=2.38
ATK_VER=${ATK_VER_MM}.0
GTK_VER_Major=4
GTK_VER_Minor=20
GTK_VER_Patch=3
GTK_VER=${GTK_VER_Major}.${GTK_VER_Minor}.${GTK_VER_Patch}
MMDB_VER=2.0.22
GSL_VER=2.8
#GEMMI_VER=0.6.3
GEMMI_VER=0.7.4
#LIBCCP4_VER=6.5.1
LIBCCP4_VER=8.0.0
LIBSSM_VER=1.4
LIBCLIPPER_VER_PRE=2.1
LIBCLIPPER_VER_PATCH=20201109
LIBCLIPPER_VER=${LIBCLIPPER_VER_PRE}.${LIBCLIPPER_VER_PATCH}
FFTW_VER=2.1.5
LIBUNISTRING_VER=1.2
GC_VER=8.2.8
GLM_VER=1.0.3
PCRE2_VER=10.47
LIBFFI_VER=3.5.2
BOOST_VER_=`echo $BOOST_VER | tr . _`
LIBDRM_VER=2.4.131
WAYLAND_VER=1.24.0
WAYLANDPROTOCOLS_VER=1.47
LIBXCB_VER=1.17.0
LIBXSHMFENCE_VER=1.3.2
LIBXXF86VM_VER=1.1.5
XCBPROTO_VER=1.17.0
MESA_VER=26.0.3
MESAGLU_VER=9.0.3
LIBVDPAU_VER=1.5
LIBXEXT_VER=1.3.7
XPROTO_VER=7.0.31
XF86VIDMODEPROTO_VER=2.3.1
XEXTPROTO_VER=7.3.0
EXPAT_VER=2.7.5
GLPROTO_VER=1.4.17
DRI2PROTO_VER=2.8
ELFUTILS_VER=0.194
XKBCOMMON_VER=1.13.1

# -------------------------------------------------------------------------------------
# As mentioned above, everything happens inside the current directory:
export PREFIX=`pwd`
export BUILD_DIR=${PREFIX}/build
export DEPS_DIR=${PREFIX}/deps
export COOT_DOWNLOAD_DIR=$PREFIX
export COOT_BUILD_DIR=$COOT_DOWNLOAD_DIR/$COOT_DIR
export CARGO_HOME=${PREFIX}/.cargo

cat <<e

  host ................................. `hostname`
  date ................................. `date`
  directory ............................ `pwd`
  user ................................. `id -nu`
  os.................................... $os

  COOT_GIT ............................. $COOT_GIT
  COOT_VER ............................. $COOT_VER
  COOT_TAG ............................. $COOT_TAG
  COOT_BRANCH .......................... $COOT_BRANCH

  PREFIX ............................... $PREFIX
  BUILD_DIR ............................ $BUILD_DIR
  DEPS_DIR ............................. $DEPS_DIR
  COOT_DOWNLOAD_DIR .................... $COOT_DOWNLOAD_DIR
  COOT_BUILD_DIR ....................... $COOT_BUILD_DIR
  CARGO_HOME ........................... $CARGO_HOME

e

# -------------------------------------------------------------------------------------
# figure out usable compiler version (in order of preference):
for __v in 16 15 14 13 12 11 
do
  type g++-${__v} >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    type gcc-${__v} >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      type gfortran-${__v} >/dev/null 2>&1
      if [ $? -eq 0 ]; then
        if [ $? -eq 0 ]; then
          [ "X$CXX" = "X" ] && [ "`g++-${__v} --version 2>&1 | head -n 1 | sed "s/g++-${__v}/g++/g"`" != "`g++ --version 2>&1 | head -n 1`" ] && export CXX="g++-${__v}" || export CXX="g++"
          [ "X$CC"  = "X" ] && [ "`gcc-${__v} --version 2>&1 | head -n 1 | sed "s/gcc-${__v}/gcc/g"`" != "`gcc --version 2>&1 | head -n 1`" ] && export CC="gcc-${__v}" || export CC="gcc"
          [ "X$FC"  = "X" ] && [ "`gfortran-${__v} --version 2>&1 | head -n 1`" != "`gfortran --version 2>&1 | head -n 1`" ] && export FC="gfortran-${__v}" || export FC="gfortran"
          export GCC_COMPILER_VERSION=${__v}
          export GCC_COMMAND_EXT="-${__v}"
          break
        fi
      else
        echo " WARNING: although we found a C/C++ compiler (\"gcc-${__v}\", \"g++-${__v}\"), the Fortran compiler (\"gfortran-${__v}\") is missing!"
      fi
    fi
  else
    type gcc-${__v} >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      echo " WARNING: although we found a C compiler (\"gcc-${__v}\"), the C++ compiler (\"g++-${__v}\") is missing!"
    fi
  fi
  type g++ >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    if [ `g++ --version 2>&1 | head -n1 | grep -c " ${__v}\."` -eq 1 ]; then
      export GCC_COMPILER_VERSION=${__v};export GCC_COMMAND_EXT=""
      break
    fi
  fi
  type g++-${__v} >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    export GCC_COMPILER_VERSION=${__v};export GCC_COMMAND_EXT="-${__v}"
    break
  fi
done
[ "X$GCC_COMPILER_VERSION" = "X" ] && error "no working (?) gcc/g++ version 13/12/11/14/15 found?"
printf "\n ### Compiler version found/used = $GCC_COMPILER_VERSION\n\n"
if [ $GCC_COMPILER_VERSION -lt 15 ]; then
  if [ $GCC_COMPILER_VERSION -lt 11 ]; then
    printf "\n ### WARNING: compiler version below the preferred minimum version 11\n"
  else
    printf "\n ### NOTE: compiler version below the preferred version 15\n"
  fi
  type scl >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    printf "\n ### NOTE: you might be able to switch to a preferred compiler version via\n\n"
    printf "    scl enable gcc-toolset-15 bash\n\n"
  fi
elif [ $GCC_COMPILER_VERSION -gt 15 ]; then
  printf "\n ### WARNING: compiler version above the preferred version 15\n"
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
    build_save_mylogs_and_rm
    printf "  meson setup (see `mypwd`/my_meson_setup.log${MY_DONE_EXT}) ... "
    meson setup --prefix=$PREFIX --buildtype=release $@ . $DEPS_DIR/${__p}-${__v} > my_meson_setup.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_meson_setup.log${MY_DONE_EXT}"
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
build_save_mylogs_and_rm () {
  # save the previous my_* files (if existing)
  if [ "X$MY_DONE_EXT" != "X" ]; then
    for __f in `ls my_*.log 2>/dev/null`
    do
      [ ! -f ${__f}1 ] && mv $__f ${__f}1
    done
    mkdir -p $PREFIX/__$$.tmpdir >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      for __i in `seq 1 $MY_DONE_EXT`
      do
        mv my_*.log${__i} $PREFIX/__$$.tmpdir/. 2>/dev/null
      done
    fi
  fi
  rm -rf *
  # re-instate old my*.log* files
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
    build_save_mylogs_and_rm
    if [ $__do_autogen -eq 1 ]; then
      printf "  autogen.sh (see `mypwd`/my_autogen.log${MY_DONE_EXT}) ... "
      $DEPS_DIR/${__p}-${__v}/autogen.sh --prefix=$PREFIX > my_autogen.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_autogen.log${MY_DONE_EXT}"
      echo "done"
    fi
    printf "  configure (see `mypwd`/my_configure.log${MY_DONE_EXT}) ... "
    $DEPS_DIR/${__p}-${__v}/configure --prefix=$PREFIX $@ > my_configure.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_configure.log${MY_DONE_EXT}"
    echo "done"

    # make sure that we don't have -g as a flag
    case $btype in
      opt) [ -f Makefile ] && \
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
    build_save_mylogs_and_rm
    printf "  cmake (see `mypwd`/my_cmake.log${MY_DONE_EXT}) ... "
    cmake $DEPS_DIR/${__p}-${__v} \
          -DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_BUILD_TYPE=release $@ > my_cmake.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_cmake.log${MY_DONE_EXT}"
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
  --without-static-libpython --enable-shared
}

build_libjpeg () {
  build_with_cmake libjpeg-turbo ${LIBJPEG_VER} \
    -DCMAKE_INSTALL_LIBDIR=$PREFIX/lib \
    -DENABLE_STATIC=OFF \
    -DWITH_JAVA=OFF
}

build_libunistring () {
  build_with_configure libunistring ${LIBUNISTRING_VER}
}

build_gc () {
  build_with_configure gc ${GC_VER}
}

build_glm () {
  build_with_cmake glm ${GLM_VER}
}

build_pcre2 () {
  build_with_configure pcre2 ${PCRE2_VER} -enable-unicode --enable-jit --enable-pcre2-16 --enable-pcre2-32 --enable-pcre2grep-libz --enable-pcre2grep-libbz2 --disable-static
}

build_libffi () {
  build_with_configure libffi ${LIBFFI_VER}
}
build_freeglut () {
  build_with_cmake freeglut ${FREEGLUT_VER} -DFREEGLUT_BUILD_DEMOS=OFF -DFREEGLUT_BUILD_STATIC_LIBS=OFF
}
build_libdrm () {
  build_with_meson libdrm ${LIBDRM_VER} -Dudev=true -Dvalgrind=disabled
}
build_wayland () {
  build_with_meson wayland ${WAYLAND_VER} -Dtests=false -Ddocumentation=false
}
build_waylandprotocols () {
  build_with_meson wayland-protocols ${WAYLANDPROTOCOLS_VER}
}
build_xcbproto () {
  PYTHON=python3 build_with_configure xcb-proto ${XCBPROTO_VER}
}
build_xproto () {
  build_with_configure xproto ${XPROTO_VER}
}
build_xf86vidmodeproto () {
  build_with_configure xf86vidmodeproto ${XF86VIDMODEPROTO_VER}
}
build_xextproto () {
  build_with_configure xextproto ${XEXTPROTO_VER}
}
build_libxext () {
  build_with_configure libXext ${LIBXEXT_VER}
}
build_glproto () {
  build_with_configure glproto ${GLPROTO_VER}
}
build_dri2proto () {
  build_with_configure dri2proto ${DRI2PROTO_VER}
}
build_elfutils () {
  build_with_configure elfutils ${ELFUTILS_VER} --disable-debuginfod
}

build_libxshmfence () {
  build_with_configure libxshmfence ${LIBXSHMFENCE_VER} --without-doxygen
}
build_libxxf86vm () {
  build_with_configure libXxf86vm ${LIBXXF86VM_VER} --without-doxygen
}
build_libxcb () {
  build_with_configure libxcb ${LIBXCB_VER} --without-doxygen
}
build_mesa () {
  build_with_meson mesa ${MESA_VER} -Dplatforms=x11,wayland -Dgallium-drivers=auto -Dvulkan-drivers="" -Dvalgrind=disabled -Dlibunwind=disabled -Dllvm=disabled
}
build_mesaglu () {
  build_with_meson glu ${MESAGLU_VER} -Dgl_provider=gl
}
build_libvdpau () {
  build_with_meson libvdpau ${LIBVDPAU_VER}
}
build_expat () {
 build_with_configure expat ${EXPAT_VER} --disable-static
}

# see https://docs.gtk.org/glib/building.html
build_glib () {
  build_with_meson glib ${GLIB_VER} -Dintrospection=disabled
}
build_glib2 () {
  build_with_meson glib ${GLIB_VER} -Dintrospection=enabled
}

build_gobject_introspection () {
  build_with_meson gobject_introspection ${GOBJECT_INTROSPECTION_VER}
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
  build_with_configure guile ${GUILE_VER} --enable-shared --disable-static --disable-error-on-warning --enable-mini-gmp
}

build_swig () {
  build_with_configure swig ${SWIG_VER}
}

build_boost () {
  if [ ! -f $BUILD_DIR/boost/.my_done${MY_DONE_EXT} ]; then
    rm -rf $BUILD_DIR/boost
    cp -a $DEPS_DIR/boost_${BOOST_VER_} $BUILD_DIR/boost || error
    cd $BUILD_DIR/boost || error

    printf "   bootstrapping boost (see `mypwd`/my_bootstrap.log${MY_DONE_EXT}) ... "
    ./bootstrap.sh --with-toolset=gcc${GCC_COMMAND_EXT} --with-libraries=serialization,regex,chrono,date_time,filesystem,iostreams,program_options,thread,math,random,system,atomic,container,context,fiber,coroutine,json,python,random > my_bootstrap.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_bootstrap.log${MY_DONE_EXT}"
    echo "done"

    if [ "X${GCC_COMMAND_EXT}" != "X" ]; then
      echo "using gcc : ${GCC_COMPILER_VERSION} : /usr/bin/g++${GCC_COMMAND_EXT} ; " >> user-config.jam || error "see above and `mypwd`/user-config.jam"
      sed -i "s/gcc${GCC_COMMAND_EXT}/gcc/g" project-config.jam || error
    fi

    printf "   building boost (see `mypwd`/my_build.log${MY_DONE_EXT}) ... "
    BOOST_BUILD_PATH=. ./b2 link=shared variant=release threading=multi runtime-link=shared install --prefix=${PREFIX} > my_build.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_build.log${MY_DONE_EXT}"
    echo "done"

    cd $BUILD_DIR || error
    touch $BUILD_DIR/boost/.my_done${MY_DONE_EXT}
  fi
}

build_libepoxy () {
  build_with_meson libepoxy ${LIBEPOXY_VER}
}

# not sure if we really need to build harfbuzz twice ...
build_harfbuzz () {
  build_with_meson harfbuzz ${HARFBUZZ_VER} -Dtests=disabled -Dcpp_std=c++17
}
build_harfbuzz2 () {
  build_with_meson harfbuzz ${HARFBUZZ_VER} -Dtests=disabled -Dcpp_std=c++17
}

build_graphene () {
  build_with_meson graphene ${GRAPHENE_VER} -Dgtk_doc=false
}

build_freetype () {
  build_with_cmake freetype ${FREETYPE_VER} -DBUILD_SHARED_LIBS=true
}

build_fontconfig () {
  build_with_meson fontconfig ${FONTCONFIG_VER} -Ddoc=disabled
}

extract_fonts () {
  ( mkdir -p $PREFIX/share/fonts/truetype/inter && \
      cd $PREFIX/share/fonts/truetype/inter && \
      tar -xf $DEPS_DIR/Inter-${FONTS_INTER_VER}.tar.gz )
  ( mkdir -p $PREFIX/share/fonts/truetype/jetbrains-mono && \
      cd $PREFIX/share/fonts/truetype/jetbrains-mono && \
      tar -xf $DEPS_DIR/JetBrainsMono-${FONTS_JETBRAINS_VER}.tar.gz )
  ( mkdir -p $PREFIX/share/fonts/truetype/dejavu && \
      cd $PREFIX/share/fonts/truetype/dejavu && \
      tar -xf $DEPS_DIR/dejavu-fonts-ttf-${FONTS_DEJAVU_VER}.tar.bz2 )
  ( mkdir -p $PREFIX/share/fonts/truetype/dejavu && \
      cd $PREFIX/share/fonts/truetype/dejavu && \
      tar -xf $DEPS_DIR/dejavu-lgc-fonts-ttf-${FONTS_DEJAVU_VER}.tar.bz2 )
  ( mkdir -p $PREFIX/share/fonts/truetype && \
      cd $PREFIX/share/fonts/truetype && \
      tar -xf $DEPS_DIR/Noto.tar.gz )
}

build_pixman () {
  build_with_meson pixman ${PIXMAN_VER}
}

build_poppler () {
  build_with_cmake poppler ${POPPLER_VER} -DENABLE_NSS3=OFF \
  -DENABLE_GPGME=OFF -DBUILD_GTK_TESTS=OFF -DBUILD_QT5_TESTS=OFF \
  -DBUILD_QT6_TESTS=OFF -DENABLE_BOOST=ON -DENABLE_QT5=OFF -DENABLE_QT6=OFF \
  -DENABLE_LIBOPENJPEG=none -DENABLE_LCMS=OFF -DENABLE_LIBCURL=ON -DENABLE_DCTDECODER=libjpeg
}

build_curl () {
    build_with_cmake curl ${CURL_VER}
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

    printf "  running configure (see `mypwd`/my_configure.log${MY_DONE_EXT}) ... "
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

# not sure if we really need to build twice ...
build_cairo () {
  build_with_meson cairo ${CAIRO_VER} --wrap-mode=nodownload -Dtests=disabled -Dxlib-xcb=enabled
}
build_cairo2 () {
  build_with_meson cairo ${CAIRO_VER} --wrap-mode=nodownload -Dtests=disabled -Dxlib-xcb=enabled
}

build_pango () {
  build_with_meson pango ${PANGO_VER} -Dintrospection=enabled
}

build_smi () {
  build_with_meson shared-mime-info ${SMI_VER}
}

build_librsvg () {
  build_with_autogen_and_configure librsvg ${LIBRSVG_VER}
}

# not sure if we really need to build twice ...
build_gdk_pixbuf () {
  build_with_meson gdk-pixbuf ${GDK_PIXBUF_VER} -Dtests=false -Dman=false -Dgtk_doc=false -Dman=false -Dglycin=disabled
}
build_gdk_pixbuf2 () {
  build_with_meson gdk-pixbuf ${GDK_PIXBUF_VER} -Dtests=false -Dman=false -Dgtk_doc=false -Dman=false -Dglycin=disabled
}

build_atk () {
  build_with_meson atk ${ATK_VER}
}
build_xkbcommon () {
  build_with_meson libxkbcommon-xkbcommon ${XKBCOMMON_VER} -Denable-docs=false -Dbash-completion-path=${PREFIX}/share
}

build_gtk () {
  build_with_meson gtk ${GTK_VER} -Dbroadway-backend=true -Dwin32-backend=false -Dmacos-backend=false \
    -Dmedia-gstreamer=disabled  -Dintrospection=enabled -Dvulkan=disabled -Dbuild-tests=false \
    -Dbuild-testsuite=false -Dbuild-examples=false -Dbuild-demos=false -Dprint-cups=disabled
}


build_pygobject () {
  build_with_meson pygobject ${PYGOBJECT_VER}
}

 
build_rdkit () {
  build_with_cmake rdkit ${RDKIT_VER} -DRDK_BUILD_CAIRO_SUPPORT=ON \
  -DRDK_BUILD_INCHI_SUPPORT=OFF \
  -DRDK_INSTALL_COMIC_FONTS=OFF \
  -DRDK_INSTALL_INTREE=OFF
}

build_mmdb2 () {
  build_with_configure mmdb2 ${MMDB_VER} --enable-shared
}


build_gsl () {
  build_with_configure gsl ${GSL_VER}
}

build_gemmi () {
  build_with_cmake gemmi ${GEMMI_VER} -DBUILD_SHARED_LIBS=true
}

build_libccp4 () {
  additional_build_env_setup
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

    printf "  configure libssm ... "
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

    printf "  configure clipper with FC=$FC CC=$CC CXX=$CXX ... "
    CXXFLAGS="-g -O2 -fno-strict-aliasing -Wno-narrowing -I$PREFIX/include" \
    CFLAGS="-g -O2 -fno-strict-aliasing -Wno-narrowing -I$PREFIX/include" \
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
  #FFTW_CONFIGURE="./configure F77=gfortran${GCC_COMMAND_EXT} --prefix=$PREFIX --enable-shared --disable-static --enable-openmp --enable-threads --with-gcc --with-gcc-ld"
  FFTW_CONFIGURE="./configure F77=gfortran${GCC_COMMAND_EXT} --prefix=$PREFIX --enable-shared --disable-static --with-gcc --with-gcc-ld"
  if [ ! -f $BUILD_DIR/fftw/.my_done${MY_DONE_EXT} ]; then
    printf "\n ### building fftw with configure/make ... "
    rm -rf $BUILD_DIR/fftw
    cp -a $DEPS_DIR/fftw-${FFTW_VER} $BUILD_DIR/fftw || error
    cd $BUILD_DIR/fftw || error
    ${FFTW_CONFIGURE} > my_configure.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_configure.log${MY_DONE_EXT}"
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
    ${FFTW_CONFIGURE} --enable-type-prefix --enable-float > my_configure.log${MY_DONE_EXT} 2>&1 || error "see `mypwd`/my_configure.log${MY_DONE_EXT}"
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
  __url=$1;shift
  if [ $# -ge 1 ]; then
    __out=$1;shift
  else
    __out=`basename $__url`
  fi
  if [ $# -ge 1 ]; then
    __ntry=$1;shift
  else
    # try three-times as default:
    __ntry=3
  fi
  
  __p=`basename $__out | sed "s/[_.0-9]/ /g" | sed "s/- //g" | awk '{print $1}'`
  echo "do_wget \"$__p\" \"$__out\" \"$__url\"" >> /tmp/`basename ${0%.sh}`.debug
  if [ ! -f $__out ]; then
    case `wget --version | awk '/^GNU/{print $3;exit}'` in
      2.*) __wget="wget --no-compression";;
      *) __wget="wget";;
    esac
    isuccess=0
    case `echo "$os" | tr '[A-Z]' '[a-z]'` in
      fedora-43*) __wget_retry_on_host_error="";;
      *) __wget_retry_on_host_error="--retry-on-host-error";;
    esac
    __common_wget_flags="--retry-connrefused --retry-on-http-error=503,429  $__wget_retry_on_host_error --waitretry=2 --read-timeout=30 --timeout=45 -t 5"
    printf "\n getting $__out ... "
    # first try to get it from $url_contrib
    __url_from="${url_contrib}/`basename $__url`"
    $__wget $__common_wget_flags -O "$__out" ${url_contrib}/$__out > my_get_${__p}.log 2>&1
    if [ $? -ne 0 ] || [ ! -s $__out ]; then
      rm -fv "$__out" >> my_get_${__p}.log 2>&1
      $__wget $__common_wget_flags -O "$__out" ${url_contrib}/`basename $__url` >> my_get_${__p}.log 2>&1
      if [ $? -ne 0 ] || [ ! -s $__out ]; then
        rm -fv "$__out" >> my_get_${__p}.log 2>&1
        for __itry in `seq 1 $__ntry`
        do
          __url_from="$__url"
          $__wget $__common_wget_flags -O "$__out" "$__url" >> my_get_${__p}.log 2>&1
          if [ $? -eq 0 ] && [ -s "$__out" ]; then
            isuccess=1
            break
          fi
          rm -fv "$__out" >> my_get_${__p}.log 2>&1
          if [ $__itry -eq $__ntry ]; then
            error "see `mypwd`/my_get_${__p}.log"
          fi
          sleep `expr $__itry \* 5`
        done
      else
        isuccess=1
      fi
    else
      isuccess=1
    fi
    echo "from \"$__url_from\" ... done"
  fi
  if [ -f $__out ]; then
    case "$__out" in
      *.tar*|*.tgz)
        __dir=`tar -tvf "$__out" 2>&1 | head -n 1 | cut -f2- -d':' | sed "s%/.*%%g" | awk '{print $NF}'`
        if [ "X$__dir" = "X" ]; then
          ls -l "$__out"
          file "$__out"
          error "unable to understand (expected) tarball $__out"
        else
          if [ ! -d $__dir/ ]; then
            printf "   unpacking $__out ... "
            tar -xf "$__out"
            if [ $? -ne 0 ]; then
              ls -l "$__out"
              file "$__out"
              error "see above"
            fi
            echo "done"
            isuccess=1
          fi
        fi
        ;;
    esac
    [ $do_wgotten -gt 0 ] && echo "`mypwd`/$__out" >> /tmp/`basename ${0%.sh}`.wgotten
  else
    if [ $isuccess -eq 0 ]; then
      # make sure to remove any (partial) files ...
      rm -f $__out
    fi
  fi
  return 0
}

initial_setup () {
  
  mkdir -p $PREFIX    || error
  mkdir -p $DEPS_DIR  || error
  mkdir -p $BUILD_DIR || error

#  install_dependencies_with_distro_package_manager
  
  cd $DEPS_DIR || error

  # Some distros ship ancient python. We need a fairly new version of pip and python.
  do_wget https://www.python.org/ftp/python/${PYTHON_VER}/Python-${PYTHON_VER}.tar.xz
  if [ -d Python-${PYTHON_VER} ] && [ ! -d python-${PYTHON_VER} ]; then
    mv Python-${PYTHON_VER} python-${PYTHON_VER} && \
      ln -s python-${PYTHON_VER} Python-${PYTHON_VER} || error
  fi
  
  cd $PREFIX || error

  if [ ! -x $PREFIX/bin/python3 ]; then
    printf "\n"
    build_python || error
    # For Boost.Python to build
    ln -sf $PREFIX/bin/python3 $PREFIX/bin/python
    ln -sf $PREFIX/bin/pip3 $PREFIX/bin/pip
  fi

  if [ ! -f $PREFIX/.my_pip_install_done ]; then
    printf "\n pip installing meson et al (see `mypwd`/my_pip_install.log) ... "
    python3 -m pip install meson setuptools numpy==${NUMPY_VER} packaging requests xattr mako > my_pip_install.log 2>&1 || error "see `mypwd`/my_pip_install.log"
    echo "done"
    touch $PREFIX/.my_pip_install_done
  fi

  # python3 -m pip install meson numpy

  # Newer CMake
  if [ ! -f $BUILD_DIR/cmakebuild/.my_done ]; then
    printf "\n ### building newer CMake\n"
    mkdir $BUILD_DIR/cmakebuild || error
    cd $BUILD_DIR/cmakebuild || error

    do_wget https://github.com/Kitware/CMake/archive/refs/tags/v${CMAKE_VER}.tar.gz
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

  # Newer Ninja
  if [ ! -f $BUILD_DIR/ninjabuild/.my_done ]; then
    printf "\n ### building newer Ninja\n"
    mkdir $BUILD_DIR/ninjabuild || error
    cd $BUILD_DIR/ninjabuild || error
    do_wget https://github.com/ninja-build/ninja/archive/refs/tags/v${NINJA_VER}.tar.gz
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

  cd $PREFIX || error
  if [ ! -f rustup-init.sh ]; then
    printf "\n### Installing RUST (hopefully into CARGO_HOME=$CARGO_HOME)\n"
    # Rust for librsvg - installs into $HOME it seems?!
    do_wget https://sh.rustup.rs rustup-init.sh 5
    chmod +x rustup-init.sh || error
    RUSTUP_INIT_SKIP_PATH_CHECK=yes ./rustup-init.sh --profile default -y --no-modify-path > my_rust_install.log 2>&1 || error "see `mypwd`/my_rust_install.log"
  fi
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

  # GCC_COMPILER_VERSION is defined in image-specific configuration, sourced above
  if [ "X$CC" = "X" ]; then
    CC=gcc${GCC_COMMAND_EXT}
    type $CC  2>&1 | awk '{print " # $CC  :",$0}' || error
    [ $do_distro -eq 1 ] && CC="$CC -mtune=generic" || CC="$CC -march=native -mtune=native"
  fi
  export CC
  echo " # CC=\"$CC\""

  if [ "X$CXX" = "X" ]; then
    CXX=g++${GCC_COMMAND_EXT}
    type $CXX 2>&1 | awk '{print " # $CXX :",$0}'  || error
    [ $do_distro -eq 1 ] && CXX="$CXX -mtune=generic" || CXX="$CXX -march=native -mtune=native"
  fi
  export CXX
  echo " # CXX=\"$CXX\""

  if [ "X$FC" = "X" ]; then
    FC=gfortran${GCC_COMMAND_EXT}
    type $FC  2>&1 | awk '{print " # $FC  :",$0}'  || error
    [ $do_distro -eq 1 ] && FC="$FC -mtune=generic" || FC="$FC -march=native -mtune=native"
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
  export FFLAGS="-std=f2008 -fallow-argument-mismatch"
  export CFLAGS="-I${PREFIX}/include"
  export CXXFLAGS="-I${PREFIX}/include"
  IFS=":"
  for i in $PKG_CONFIG_LIBDIR
  do
    # ensure we only add non-standard directories and do this only once
    case $i in
      ${PREFIX}/*) [ `echo " $LDFLAGS " | grep -c " -L${i} "` -eq 0 ] && export LDFLAGS="-L${i} ${LDFLAGS}";;
    esac
  done
  unset IFS
  export GLM_CFLAGS="-I${PREFIX}/include"
  export GLM_LIBS="-L${PREFIX}/lib"
}


#TODO:
# * JPEG for poppler (and tiff)
# * curl, libbackward
# * Additional deps: libeigen, coordgen

download_dependencies () {
  cd $DEPS_DIR || error

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

  # Boost
  do_wget https://archives.boost.io/release/${BOOST_VER}/source/boost_${BOOST_VER_}.tar.bz2

  # Freetype2
  #   This one is a special snowflake which really likes to fail...
  do_wget https://download.savannah.gnu.org/releases/freetype/freetype-${FREETYPE_VER}.tar.xz freetype-${FREETYPE_VER}.tar.xz 8
  
  # Fontconfig
  #do_wget https://www.freedesktop.org/software/fontconfig/release/fontconfig-${FONTCONFIG_VER}.tar.xz
  do_wget https://codeload.github.com/fontconfig/fontconfig/tar.gz/refs/tags/${FONTCONFIG_VER} fontconfig-${FONTCONFIG_VER}.tar.gz

  # Fonts
  do_wget https://github.com/rsms/inter/releases/download/v${FONTS_INTER_VER}/Inter-${FONTS_INTER_VER}.tar.gz
  do_wget https://download.jetbrains.com/fonts/JetBrainsMono-${FONTS_JETBRAINS_VER}.tar.gz
  do_wget https://github.com/dejavu-fonts/dejavu-fonts/releases/download/version_`echo ${FONTS_DEJAVU_VER} | sed "s/\./_/g"`/dejavu-fonts-ttf-${FONTS_DEJAVU_VER}.tar.bz2
  do_wget https://github.com/dejavu-fonts/dejavu-fonts/releases/download/version_`echo ${FONTS_DEJAVU_VER} | sed "s/\./_/g"`/dejavu-lgc-fonts-ttf-${FONTS_DEJAVU_VER}.tar.bz2
  do_wget https://github.com/notofonts/NotoSansMono/archive/refs/heads/Noto.tar.gz

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
  
  # Pango
  do_wget https://download.gnome.org/sources/pango/${PANGO_VER_MM}/pango-${PANGO_VER}.tar.xz

  # Librsvg
  do_wget https://gitlab.gnome.org/GNOME/librsvg/-/archive/${LIBRSVG_VER}/librsvg-${LIBRSVG_VER}.tar.gz

  # GDK-Pixbuf
  do_wget https://download.gnome.org/sources/gdk-pixbuf/${GDK_PIXBUF_VER_MM}/gdk-pixbuf-${GDK_PIXBUF_VER}.tar.xz

  # Atk
  do_wget https://download.gnome.org/sources/atk/${ATK_VER_MM}/atk-${ATK_VER}.tar.xz

  # xkbcommon
  do_wget https://github.com/xkbcommon/libxkbcommon/archive/refs/tags/xkbcommon-${XKBCOMMON_VER}.tar.gz
  
  # Gtk
  do_wget https://download.gnome.org/sources/gtk/${GTK_VER_Major}.${GTK_VER_Minor}/gtk-${GTK_VER}.tar.xz

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
  do_wget "https://aur.archlinux.org/cgit/aur.git/plain/ssm.pc.in?h=libssm" ssm.pc.in 5
  cp -p ssm.pc.in libssm-${LIBSSM_VER}/ssm.pc.in || error

  # Libclipper
  do_wget https://deb.debian.org/debian/pool/main/c/clipper/clipper_${LIBCLIPPER_VER}.orig.tar.gz libclipper-${LIBCLIPPER_VER}.tar.gz
  #do_wget https://www2.mrc-lmb.cam.ac.uk/personal/pemsley/coot/dependencies/clipper-${LIBCLIPPER_VER}.tar.gz libclipper-${LIBCLIPPER_VER}.tar.gz

  # FFTW
  do_wget http://www.fftw.org/fftw-${FFTW_VER}.tar.gz

  # gc
  do_wget https://www.hboehm.info/gc/gc_source/gc-${GC_VER}.tar.gz

  # expat
  do_wget https://github.com/libexpat/libexpat/releases/download/R_`echo ${EXPAT_VER}| sed "s/\./_/g"`/expat-${EXPAT_VER}.tar.gz
  
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

  for __p in libffi freeglut
  do
    __puc=`echo $__p | tr '[a-z]' '[A-Z]'`
    eval "__v=\"\$${__puc}_VER\""  
    do_wget https://github.com/${__p}/${__p}/releases/download/v${__v}/${__p}-${__v}.tar.gz
  done

  # elfutils
  do_wget https://sourceware.org/ftp/elfutils/${ELFUTILS_VER}/elfutils-${ELFUTILS_VER}.tar.bz2
  
  # libdrm
  do_wget https://dri.freedesktop.org/libdrm/libdrm-${LIBDRM_VER}.tar.xz

  ### xorg.freedesktop.org/archive/individual/proto
  for __p in xcb-proto xproto xf86vidmodeproto xextproto glproto dri2proto
  do
    __puc=`echo $__p | sed "s/-//g" | tr '[a-z]' '[A-Z]'`
    eval "__v=\"\$${__puc}_VER\""  
    do_wget https://xorg.freedesktop.org/archive/individual/proto/${__p}-${__v}.tar.gz
  done

  ### xorg.freedesktop.org/archive/individual/lib
  for __p in libxcb libxshmfence libXxf86vm libXext
  do
    __puc=`echo $__p | tr '[a-z]' '[A-Z]'`
    eval "__v=\"\$${__puc}_VER\""  
    do_wget https://xorg.freedesktop.org/archive/individual/lib/${__p}-${__v}.tar.gz
  done

  # Mesa
  do_wget https://archive.mesa3d.org/mesa-${MESA_VER}.tar.xz
  # glu
  do_wget https://archive.mesa3d.org/glu/glu-${MESAGLU_VER}.tar.xz

  #### gitlab.freedesktop.org

  # Shared-mime-info
  do_wget https://gitlab.freedesktop.org/xdg/shared-mime-info/-/archive/${SMI_VER}/shared-mime-info-${SMI_VER}.tar.gz

  for __p in libvdpau wayland
  do
    __puc=`echo $__p | tr '[a-z]' '[A-Z]'`
    eval "__v=\"\$${__puc}_VER\""  
    do_wget https://gitlab.freedesktop.org/${__p#lib}/${__p}/-/archive/${__v}/${__p}-${__v}.tar.gz
  done

  do_wget https://gitlab.freedesktop.org/wayland/wayland-protocols/-/releases/${WAYLANDPROTOCOLS_VER}/downloads/wayland-protocols-${WAYLANDPROTOCOLS_VER}.tar.xz
}

build_dependencies () {
  # order matters - and some have to be done multiple times it seems
  for __p in $BUILD_DEPENDENCIES
  do
    __pp=`echo $__p | sed "s/-//g"`
    eval "__n=\$__n_${__pp}"
    [ "X$__n" = "X" ] && __n=0
    __n=`expr $__n + 1`
    case $__n in
      1) __t="";;
      *) __t=" again (#$__n)";export MY_DONE_EXT=$__n;;
    esac
    [ ! -f $BUILD_DIR/$__p/.my_done${MY_DONE_EXT} ] && [ $iverb -gt 0 ] && printf "\n >>> building $__p${__t}\n"
    eval "build_${__p}${__n#1}" || error
    eval "__n_${__pp}=\$__n"
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
  case `uname` in
    Linux)
      ls /usr/lib*/liblas.so >/dev/null 2>&1
      if [ $? -ne 0 ]; then
        if [ ! -f $PREFIX/lib/libblas.so ]; then
          if [ -f /usr/lib64/libblas.so.3 ]; then
            ln -s /usr/lib64/libblas.so.3 $PREFIX/lib/libblas.so
          elif [ -f /usr/lib/libblas.so.3 ]; then
            ln -s /usr/lib/libblas.so.3 $PREFIX/lib/libblas.so
          fi
        fi
      fi
      ;;
  esac
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
  #--with-libdw --with-backward
  if [ ! -f .my_configure_done ]; then
    printf " ### Coot: configure (see `mypwd`/my_configure.log) ... "
    [ $do_distro -eq 1 ] && __arch="-mtune=generic" || __arch="-march=native -mtune=native"
    case $btype in
      opt) __opt="-g -O3 -ffast-math";;
      *) __opt="";;
    esac
    cat <<EOF > my_configure.sh
#!/bin/sh

PREFIX=$PREFIX
FFLAGS="$FFLAGS" \\
CFLAGS="$CFLAGS" \\
CXXFLAGS="$CXXFLAGS" \\
LDFLAGS="$LDFLAGS" \\
SHELL=/bin/sh \\
PYTHON=python3 \\
CXXFLAGS="${CXXFLAGS} ${__opt} ${__arch} -Wreturn-type -Wl,--as-needed -Wno-sequence-point -Wsign-compare -Wno-unknown-pragmas" \\
./configure --prefix=\$PREFIX \\
            --libexecdir=\$PREFIX/libexec \\
            --disable-static \\
            --with-enhanced-ligand-tools \\
            --with-rdkit-prefix=\$PREFIX \\
            --with-boost=\$PREFIX \\
            --with-gemmi=\$PREFIX \\
            --with-boost-thread=boost_thread \\
            --with-boost-python="boost_python${PYTHON_VER_MAJOR}${PYTHON_VER_MINOR}"
EOF
    chmod +x my_configure.sh
    SHELL=/bin/sh \
    PYTHON=python3 \
    CXXFLAGS="${CXXFLAGS} ${__opt} ${__arch} -Wreturn-type -Wl,--as-needed -Wno-sequence-point -Wsign-compare -Wno-unknown-pragmas" \
    ./configure --prefix=$PREFIX \
                --libexecdir=$PREFIX/libexec \
                --disable-static \
                --with-enhanced-ligand-tools \
                --with-rdkit-prefix=$PREFIX \
                --with-boost=$PREFIX \
                --with-gemmi=$PREFIX \
                --with-boost-thread=boost_thread \
                --with-boost-python="boost_python${PYTHON_VER_MAJOR}${PYTHON_VER_MINOR}" \
                > my_configure.log 2>&1 || error "see `mypwd`/my_configure.log"
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

complete_coot () {
  # get reference structures:
  if [ ! -d $PREFIX/share/coot/reference-structures ]; then
    cd $PREFIX/share/coot || error
    do_wget https://www2.mrc-lmb.cam.ac.uk/personal/pemsley/coot/dependencies/reference-structures.tar.gz || error
    rm -f reference-structures.tar.gz || error
  fi
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
EOF
}

package_coot_prep () {
  cd $PREFIX || error

  # fix scripts that have something hard-wired
  printf "\n"
  for __f in `grep -l "$PREFIX" bin/* 2>/dev/null | grep -v "kak$"`
  do
    case `file $__f` in
      *ELF*) continue;;
    esac
    printf " # change PREFIX in $__f\n"
    sed -i -e "s%$PREFIX\$%\`dirname \$0\`%g" \
           -e "s%$PREFIX/%\`dirname \$0\`/%g" \
           -e "s%$PREFIX\"%\`dirname \$0\`\"%g" \
           $__f
  done

  # copy binaries into libexec (so that wrapper system can find them)
  for __f in `file bin/* 2>/dev/null | egrep " executable " | cut -f1 -d':'`
  do
    __f=`basename $__f`
    if [ ! -x libexec/$__f ]; then
      printf "\n # copy bin/$__f into libexec\n"
      cp -p bin/$__f libexec/$__f
    fi
  done

  # create links to wrapper system:
  __nf=0
  for __f in `file libexec/* 2>/dev/null | egrep " executable," | cut -f1 -d':'` coot-1:coot
  do
    case `basename $__f` in
      gio*) continue;;
      *:*)    __g=`echo $__f | cut -f2 -d':'`
              __f=`echo $__f | cut -f1 -d':'`;;
      coot-*) __g=`basename $__f`;;
      *)      __g="coot-`basename $__f`";;
    esac
    __f=`basename $__f`
    __f=${__f%-bin}
    __g=${__g%-bin}
    __g=${__g%-bin}
    if [ ! -h bin/$__f ] || [ "X$__f" != "X$__g" ]; then
      [ -f bin/$__g ] && mv bin/$__g bin/$__g.orig
      [ -f bin/$__f ] && mv bin/$__f bin/$__f.orig
      printf "\n # create bin/$__f link\n"
      ln -sf coot-wrapper.sh bin/$__f && __nf=`expr $__nf + 1`
      if [ ! -f bin/$__g ] && [ ! -h bin/$__g ]; then
        printf "\n # create bin/$__g wrapper\n"
        cat <<EOF > bin/$__g
#!/bin/sh
"\`dirname \$0\`/$__f" "\$@"
EOF
        chmod +x bin/$__g
      fi
    else
      printf "\n # bin/$__f already a link\n"
    fi
  done

  printf "\n ### NOTE: created $__nf symbolic links to generic wrapper tool\n"

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

package_coot () {
  cd $PREFIX || error
  if [ -f /etc/os-release ]; then
    os=`(. /etc/os-release ; echo "$NAME-${VERSION_ID}" | sed "s/ [^-]*-/-/g")`
  elif [ -f /etc/lsb-release ]; then
    os=`(. /etc/lsb-release ; echo ${DISTRIB_ID}-${DISTRIB_RELEASE})`
  else
    return
  fi
  out=coot_${os}_`uname -m`_`date +%Y%m%d_%H%M%S`.tar.gz
  __dirs="lib libexec share"
  [ -d lib64 ] && __dirs="$__dirs lib64"
  if [ -f bin/fc-match ]; then
    printf "  including FontConfig binaries, fonts and cache:\n"
    [ -d var/cache/fontconfig ] && __dirs="$__dirs var/cache/fontconfig"
    __dirs="$__dirs etc `ls bin/fc-* 2>/dev/null`"
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
      fc-cache -rv 2>&1 | awk '{print "    ",$0}' | egrep -v " skipping| 0 fonts"
    )
  fi
  create_readme
  printf "\n packaging Coot as $out ... "
  tar -czf $out bin/coot* bin/layla bin/pyrogen bin/python3* $__dirs > my_tar.log 2>&1 || error "see `mypwd`/my_tar.log"
  echo "done"
  printf "\n   "
  ls -l $out
  printf "\n"
}
package_coot_minimal () {
  cd $PREFIX || error
  if [ -f /etc/os-release ]; then
    os=`(. /etc/os-release ; echo "$NAME-${VERSION_ID}" | sed "s/ [^-]*-/-/g")`
  elif [ -f /etc/lsb-release ]; then
    os=`(. /etc/lsb-release ; echo ${DISTRIB_ID}-${DISTRIB_RELEASE})`
  else
    return
  fi
  outnam=coot-${outtag}-minimal_${os}_`uname -m`_`date +%Y%m%d_%H%M%S`
  out=$outnam.tar.gz
  __dirs="lib libexec share"
  [ -d lib64 ] && __dirs="$__dirs lib64"
  if [ -f bin/fc-match ]; then
    printf "  including FontConfig binaries, fonts and cache:\n"
    [ -d var/cache/fontconfig ] && __dirs="$__dirs var/cache/fontconfig"
    __dirs="$__dirs etc `ls bin/fc-* 2>/dev/null`"
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
      fc-cache -rv 2>&1 | awk '{print "    ",$0}' | egrep -v " skipping| 0 fonts"
    )
  fi
  mkdir -p __$$.tmp/$outnam || error
  cp -ar $__dirs __$$.tmp/$outnam/. || error "copy-1 (see above)"
  mkdir -p  __$$.tmp/$outnam/bin
  cp -a bin/coot* bin/layla bin/pyrogen bin/python3* __$$.tmp/$outnam/bin/. || error "copy-2 (see above)"
  if [ -x bin/fc-match ]; then
    cp -a bin/fc-* __$$.tmp/$outnam/bin/. || error "copy-3 (see above)"
  fi
  (
    cd __$$.tmp/$outnam || error

    printf "\n preparing for minimal size ... "
    find . -type f -name "*.[ai]" | xargs -r rm
    find . -type f -name "*.la" | xargs -r rm
    find share/locale -type d ! -name en | xargs -r rm -fr
    find share -type f -name "*html" | grep -v coot | xargs -r rm
    rm -fr share/man share/doc share/RDKit/Docs share/cmake*/Help share/cmake*/Modules
    type strip >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      egrep="egrep"
      __c=`egrep --version 2>&1 | grep -c "egrep is obsolescent"`
      [ $__c -ne 0 ] && egrep="grep -E" || egrep="egrep"
      find lib* -name "*.so*" -type f | $egrep "so$|[0-9]$" | xargs -r -n 1 strip
      find libexec -type f ! -name "*.*" | xargs -r -n 1 strip
      find bin -type f -size +100k ! -name "*.*" | xargs -r -n 1 strip
    fi
    echo "done"

    create_readme /$outnam
    cd ../ || error
    printf "\n packaging minimal Coot as $out ... "
    tar -czf ../$out * > ../my_tar.log 2>&1 || error "see `dirname $PWD`/my_tar.log"
    echo "done"
  )
  rm -fr __$$.tmp || error
  printf "\n"
  ls -l $out
  printf "\n"
}

setup_all_and_build_coot () {
  setup_build_env || error
  initial_setup || error
  download_dependencies || error
  build_dependencies || error
  cat <<e

########################################################################
### Now for the real thing: Coot
########################################################################

e
  download_coot || error
  build_coot || error
  complete_coot || error
}
create_coot_wrapper () {
  cd $PREFIX || error
  if [ ! -f bin/coot-wrapper.sh ]; then
    cat <<'EOF' > bin/coot-wrapper.sh
#!/bin/sh
# -*-shell-script-*-
# coot wrapper script 
# Copyright 2004, 2005, 2006, 2007 University of York

# 20240521 (CV): re-implemented for more checks before firing up Coot and friends
# 20260130 (CV): added packaging of fonts and FontConfig system (to be independent of OS fonts and behaviour)

# -----------------------------------------------------------------------------------
# list of variables that need to be set in the end:
vars="COOT_DATA_DIR COOT_PREFIX COOT_SCHEME_DIR COOT_STANDARD_RESIDUES PYTHONHOME GUILE_LOAD_PATH XDG_DATA_DIRS"

# all env variables starting with COOT_* defined somewhere in the code:
# COOT_BACKUP_DIR
# COOT_CCP4SRS_DIR
# COOT_CCP4_LIB_DIR
# COOT_CHEMICAL_FEATURES_DEF
# COOT_DATA_DIR
# COOT_DEBUG_REFINEMENT
# COOT_DEV_TEST
# COOT_HOME
# COOT_MONOMER_LIB_DIR
# COOT_N_THREADS
# COOT_OPENGL_MAJOR_VERSION
# COOT_OPENGL_MINOR_VERSION
# COOT_OPENGL_WIDGET_SCALE_FACTOR
# COOT_PIXMAPS_DIR
# COOT_PREFIX
# COOT_PYTHON_DIR
# COOT_PYTHON_EXTRAS_DIR
# COOT_REFMAC_LIB_DIR
# COOT_REF_SEC_STRUCTS
# COOT_REF_STRUCTS
# COOT_SBASE_DIR
# COOT_SCHEME_DIR
# COOT_SCHEME_EXTRAS_DIR
# COOT_STANDARD_RESIDUES
# COOT_TEST_DATA_DIR

# -----------------------------------------------------------------------------------
# go for safe locales:
LANG=C
LC_ALL=C
LC_NUMERIC=C
export LANG LC_ALL LC_NUMERIC

# -----------------------------------------------------------------------------------
# information about this script:
case "$0" in
  /*) iamfull="$0";;
  *) iamfull="`pwd`/$0";;
esac
iam=`basename "$iamfull"`
rdir=`dirname "$iamfull"`
case "$rdir" in
  */bin) rdir=`dirname "$rdir"`;;
esac

# -----------------------------------------------------------------------------------
# utility functions
error () {
  [ "X$@" != "X" ] && printf "\n ERROR: $@\n\n" || printf "\n ERROR: see above\n\n"
  exit 1
}
warning () {
  [ "X$@" != "X" ] && printf "\n WARNING: $@\n\n" || printf "\n WARNING: see above\n\n"
}
note () {
  [ "X$@" != "X" ] && printf "\n NOTE: $@\n\n"
}
usage () {
  printf "\n"
  printf " USAGE: $iam [-h] [-v] [--ldd|--debug|--strace] ... $@\n"
  printf "\n"
}

# -----------------------------------------------------------------------------------
# parse command-line arguments (those that are not part of the Coot binary itself)
iverb=0
do_ccp4=0
do_ldd=0
do_debug=0
do_strace=0
while [ $# -gt 0 ]
do
  case "$1" in
    -h) usage "--help";exit 0;;
    --ldd)do_ldd=1;shift;;
    --debug)do_debug=1;shift;;
    --strace)do_strace=1;shift;;
    --ccp4*) do_ccp4=1;shift;;
    -v) iverb=`expr $iverb + 1`;shift;;
    *) break;;
  esac
done

# -----------------------------------------------------------------------------------
# check required commands
ne=0
for exe in awk sed
do
  type $exe >/dev/null 2>&1
  [ $? -ne 0 ] && warning "command \"$exe\" not found" && ne=`expr $ne + 1`
done
[ $ne -gt 0 ] && error "some required commands not found - see above"

# -----------------------------------------------------------------------------------
# are we running on a supported platform?
case `uname` in

  # ---------------------------------------------------------------------------------
  Linux)

    # -------------------------------------------------------------------------------
    # LD_LIBRARY_PATH settings:  
    vars="$vars LD_LIBRARY_PATH"
    for sdir in lib lib64 lib/x86_64-linux-gnu/
    do
      [ ! -d $rdir/$sdir ] && continue
      [ "X$LD_LIBRARY_PATH" = "X" ] && LD_LIBRARY_PATH="$rdir/$sdir" && continue
      LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:$rdir/$sdir"
    done
    [ "X$LD_LIBRARY_PATH" != "X" ] && export LD_LIBRARY_PATH

    ;;

  # ---------------------------------------------------------------------------------
  Darwin)

    # -------------------------------------------------------------------------------
    # DYLD_LIBRARY_PATH settings:  
    vars="$vars DYLD_LIBRARY_PATH"
    for sdir in lib
    do
      [ ! -d $rdir/$sdir ] && continue
      [ "X$DYLD_LIBRARY_PATH" = "X" ] && DYLD_LIBRARY_PATH="$rdir/$sdir" && continue
      DYLD_LIBRARY_PATH="${DYLD_LIBRARY_PATH}:$rdir/$sdir"
    done
    [ "X$DYLD_LIBRARY_PATH" != "X" ] && export DYLD_LIBRARY_PATH

    ;;

  *) error "$iam doesn't support OS \"`uname`\"";;
esac

# -----------------------------------------------------------------------------------
# set variables
COOT_PREFIX="$rdir"

PYTHONHOME="$COOT_PREFIX"
export PYTHONHOME

PATH="$COOT_PREFIX/bin:$PATH"

if [ -f "$COOT_PREFIX/share/coot/syminfo.lib" ]; then
  SYMINFO="$COOT_PREFIX/share/coot/syminfo.lib"
  export SYMINFO
fi

COOT_SCHEME_DIR="$COOT_PREFIX/share/coot/scheme"
if [ "X$CLIBD_MON" = "X" ]; then
  COOT_REFMAC_LIB_DIR="$COOT_PREFIX/share/coot/lib"
  export COOT_REFMAC_LIB_DIR
  vars="$vars COOT_REFMAC_LIB_DIR"
fi

if [ -f "$COOT_PREFIX/share/coot/standard-residues.pdb" ]; then
  COOT_STANDARD_RESIDUES="$COOT_PREFIX/share/coot/standard-residues.pdb"
  export COOT_STANDARD_RESIDUES
fi

COOT_DATA_DIR="$COOT_PREFIX/share/coot"
export COOT_DATA_DIR

if [ -f "$COOT_PREFIX/share/coot/cootrc" ]; then
  COOT_RESOURCES_FILE="$COOT_PREFIX/share/coot/cootrc"
  vars="$vars COOT_RESOURCES_FILE"
fi
if [ -d "$COOT_PREFIX/share/coot/reference-structures" ]; then
  COOT_REF_STRUCTS="$COOT_PREFIX/share/coot/reference-structures"
  vars="$vars COOT_REF_STRUCTS"
fi
for __e in coot-1 Coot coot
do
  [ ! -x "$COOT_PREFIX/libexec/$__e" ] && continue
  __ee=`echo $__e | tr '[A-Z]' '[a-z]' | sed "s%-%%g"`
  eval "${__ee}_exe=\"\$COOT_PREFIX/libexec/\$__e\""
  eval "${__ee%1}_exe=\"\$COOT_PREFIX/libexec/\$__e\""
  break
done
for exe in coot-density-score-by-residue-bin \
           coot-ligand-validation-bin \
           coot-make-ligands-db \
           coot-identify-protein-bin \
           findligand-bin \
           findwaters-bin \
           identify-protein-bin \
           mini-rsr-bin \
           `file "$COOT_PREFIX/libexec"/* 2>/dev/null | egrep " executable " | cut -f1 -d':' | sed "s%.*/%%g"`
do
  [ ! -x "$COOT_PREFIX/libexec/$exe" ] && [ ! -x "$COOT_PREFIX/libexec/coot-$exe" ] && continue
  # with and without coot- prefix:
  e=`echo "${exe%-bin}" | sed "s/-//g"`
  eval "${e}_exe=\"\$COOT_PREFIX/libexec/$exe\""
  case "$e" in
    coot*) continue;;
  esac
  eval "coot${e}_exe=\"\$COOT_PREFIX/libexec/$exe\""
done

export GUILE_WARN_DEPRECATED=no
GUILE_LOAD_PATH="$COOT_PREFIX/share/guile/3.0"

if [ "X$COOT_GUILE_BIN" = "X" ]; then
  if [ -x "$COOT_PREFIX/libexec/guile" ]; then
    GUILE_BIN="$COOT_PREFIX/libexec/guile"
  elif [ -x "$COOT_PREFIX/bin/guile" ]; then
    GUILE_BIN="$COOT_PREFIX/bin/guile"
  fi
fi
if [ -d "$COOT_PREFIX/share" ] && [ "X$COOT_XDG_DATA_DIRS" = "X" ]; then
  XDG_DATA_DIRS="$COOT_PREFIX/share"
  export XDG_DATA_DIRS
fi
if [ -d "$COOT_PREFIX/var/cache" ] && [ "X$COOT_XDG_CACHE_HOME" = "X" ]; then
  XDG_CACHE_HOME="$COOT_PREFIX/var/cache"
  export XDG_CACHE_HOME
fi
if [ -d "$COOT_PREFIX/etc/fonts" ] && [ "X$COOT_FONTCONFIG_PATH" = "X" ]; then
  FONTCONFIG_PATH="$COOT_PREFIX/etc/fonts"
  export FONTCONFIG_PATH
fi
if [ -f "$COOT_PREFIX/etc/fonts/fonts.conf" ] && [ "X$COOT_FONTCONFIG_FILE" = "X" ]; then
  FONTCONFIG_FILE="$COOT_PREFIX/etc/fonts/fonts.conf"
  export FONTCONFIG_FILE
fi
if [ -d "$COOT_PREFIX/var/cache/fontconfig" ] && [ "X$COOT_FC_CACHEDIR" = "X" ]; then
  FC_CACHEDIR="$COOT_PREFIX/var/cache/fontconfig"
  export FC_CACHEDIR
fi
# unset FONTCONFIG_SYSROOT
# unset FONTCONFIG_SYSROOT_DIR

# GI_TYPELIB_PATH settings:  
vars="$vars GI_TYPELIB_PATH"
for sdir in lib/girepository-1.0 lib64/girepository-1.0 lib/x86_64-linux-gnu/girepository-1.0
do
  [ ! -d $rdir/$sdir ] && continue
  [ "X$GI_TYPELIB_PATH" = "X" ] && GI_TYPELIB_PATH="$rdir/$sdir" && continue
  GI_TYPELIB_PATH="${GI_TYPELIB_PATH}:$rdir/$sdir"
done
[ "X$GI_TYPELIB_PATH" != "X" ] && export GI_TYPELIB_PATH

# -----------------------------------------------------------------------------------
# do we have all variables set?
ne=0
for var in $vars
do
  eval "val=\"\$$var\""
  [ "X$val" = "X" ] && warning "no value given for variable $var" && ne=`expr $ne + 1`
done
[ $ne -gt 0 ] && error "some required settings missing - see above"

# -----------------------------------------------------------------------------------
# additional checks (*PATH/*DIR variables should point to directories)
ne=0
for var in $vars
do
  case "$var" in
    *PATH|*DIR)
      eval "val=\"\$$var\""
      for dir in `echo "$val" | sed "s/:/ /g"`
      do
        [ ! -d "$dir" ] && warning "directory/entry \"$dir\" ($var) not found" && ne=`expr $ne + 1`
      done
      ;;
  esac
done
[ $ne -gt 0 ] && error "some defined directories not found - see above"

# -----------------------------------------------------------------------------------
# report all settings
if [ $iverb -gt 0 ]; then
  printf "\n"
  for var in $vars
  do
    eval "val=\"\$$var\""
    echo "$val" | awk -v var="$var" 'BEGIN{for(i=1;i<=60;i++) x=x "."}{
      printf(" %s %s %s\n",var,substr(x,1,(length(x)-length(var))),$0)
    }' 
  done
  printf "\n"
fi

# -----------------------------------------------------------------------------------
# now actual run it:
if [ $do_ccp4 -eq 0 ]; then
  e=`echo "${iam%-bin}" | cut -f1 -d'-'`
  eval "exe=\"\$${e}_exe\""
  [ "X$exe" = "X" ] && error "executable to run \"$iam\" not defined"
  [ ! -f "$exe" ] && error "executable \"$exe\" not found"
  [ ! -x "$exe" ] && error "executable \"$exe\" not executable"

  # various options for debugging/running:
  if [ $do_ldd -eq 1 ]; then
    ldd "$exe"
  elif [ $do_strace -eq 1 ]; then
    type strace >/dev/null 2>&1 || error "no \"strace\" command found"
    strace "$exe" "$@"
  else
    if [ $do_debug -eq 1 ]; then
      printf "\n\n"
      echo " ### Running: \"$exe\" \"$@\"\n"
      printf "\n"
      fc-match -v monospace 2>/dev/null | grep file
      fc-match -v serif 2>/dev/null | grep file
      fc-match -v sans 2>/dev/null | grep file
      "$exe" "$@" || error
    else
      "$exe" "$@" 2>&1 | sed "s%Usage:[ ]*[^ ]*%Usage: $iam%g" || error
    fi
  fi
else
  error "CCP4 mode not yet supported/implemented"
fi

exit 0
EOF
    chmod +x bin/coot-wrapper.sh
  fi
}

printf "\n################## setup_all_and_build_coot ################## \n\n"
setup_all_and_build_coot || error
printf "\n####################### handling fonts ####################### \n\n"
extract_fonts || error
printf "\n###################### package_coot_prep ##################### \n\n"
package_coot_prep        || error
printf "\n#################### create_coot_wrapper ##################### \n\n"
create_coot_wrapper      || error
if [ $do_minimaltar -eq 1 ]; then
  printf "\n#################### package_coot_minimal #################### \n\n"
  package_coot_minimal   || error
else
  printf "\n######################## package_coot ######################## \n\n"
  package_coot           || error
fi
cat <<EOF

########################################################################

  To save space you could now do

    find build -type d -name .libs | xargs rm -fr
    find build -type d -name .deps | xargs rm -fr

  or just

    rm -fr coot deps build .cargo

  (to use the installation here) or even

    rm -fr coot deps build .cargo doc etc info var libexec bin include share lib lib64

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
