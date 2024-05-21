#!/usr/bin/bash  

# -------------------------------------------------------------------------------------
# This script is meant to be run interactively: all download, building
# and installation is done in current directory

error () {
  [ $# -eq 0 ] && printf "\n ERROR: see above\n\n" || printf "\n ERROR: $@\n\n"
  exit 1
}
warning () {
  [ $# -eq 0 ] && printf "\n WARNING: see above\n\n" || printf "\n WARNING: $@\n\n"
}
usage () {
  printf "\n USAGE: `basename $0` [-h] [-v] [-nthreads <N>]\n\n"
}

iverb=0
nthreads=`nproc --all`
while [ $# -gt 0 ]
do
   case $1 in
    -h|-help|--help)usage;exit 0;;
    -v)iverb=`expr $iverb + 1`;;
    -nthreads)nthreads=$2;shift;;
    *) error "unknown argument = \"$1\"";;
  esac
  shift
done

[ $iverb -ge 1 ] && set -x

# -------------------------------------------------------------------------------------
# versions of all external packages/dependencies:
CMAKE_VER=3.29.1
NINJA_VER=1.11.1

PYTHON_VER_MAJOR=3
# Todo: bring back Python 3.12 when Coot drops usage of the `imp` module
#PYTHON_VER_MINOR=12
#PYTHON_VER_PATCH=2
PYTHON_VER_MINOR=11
PYTHON_VER_PATCH=8
PYTHON_VER="${PYTHON_VER_MAJOR}.${PYTHON_VER_MINOR}.${PYTHON_VER_PATCH}"

LIBJPEG_VER=3.0.2
GLIB_VER=2.80.0
GOBJECT_INTROSPECTION_VER_MM=1.80
GOBJECT_INTROSPECTION_VER=${GOBJECT_INTROSPECTION_VER_MM}.1
GUILE_VER=3.0.9
SWIG_VER=4.1.1
BOOST_VER=1.84.0
BOOST_VER_=$(echo $BOOST_VER | tr . _)
LIBEPOXY_VER=1.5.10
GRAPHENE_VER=1.10.8
HARFBUZZ_VER=8.5.0
FREETYPE_VER=2.13.2
FONTCONFIG_VER=2.14.2
PIXMAN_VER=0.43.4
LIBTIFF_VER=4.6.0
POPPLER_VER=24.03.0
CAIRO_VER=1.18.0
PANGO_VER_MM=1.52
PANGO_VER=${PANGO_VER_MM}.2
SMI_VER=2.4
LIBRSVG_VER_MM=2.58
LIBRSVG_VER=${LIBRSVG_VER_MM}.0
GDK_PIXBUF_VER_MM=2.42
GDK_PIXBUF_VER=${GDK_PIXBUF_VER_MM}.11
ATK_VER_MM=2.38
ATK_VER=${ATK_VER_MM}.0
WAYLAND_VER=1.22.0
GTK_VER_Major=4
GTK_VER_Minor=14
GTK_VER_Patch=4
GTK_VER=${GTK_VER_Major}.${GTK_VER_Minor}.${GTK_VER_Patch}
PYGOBJECT_VER=3.46.0
RDKIT_VER=2024_03_2
MMDB_VER=2.0.22
GSL_VER=2.7.1
GEMMI_VER=0.6.3
LIBCCP4_VER=6.5.1
LIBSSM_VER=1.4
LIBCLIPPER_VER_PRE=2.1
LIBCLIPPER_VER_PATCH=20180802
LIBCLIPPER_VER=${LIBCLIPPER_VER_PRE}.${LIBCLIPPER_VER_PATCH}
FFTW_VER=2.1.5
LIBUNISTRING_VER=1.2
GC_VER=8.2.4
GLM_VER=1.0.1
PCRE2_VER=10.43

# -------------------------------------------------------------------------------------
# As mentioned above, everything happens inside the current directory:
export PREFIX=`pwd`
export BUILD_DIR=${PREFIX}/build
export DEPS_DIR=${PREFIX}/deps
export COOT_DOWNLOAD_DIR=$PREFIX
export COOT_BUILD_DIR=$COOT_DOWNLOAD_DIR/coot
export CARGO_HOME=${PREFIX}/.cargo

cat <<e

  host ................................. `hostname`
  date ................................. `date`
  directory ............................ `pwd`
  user ................................. `id -nu`

  PREFIX ............................... $PREFIX
  BUILD_DIR ............................ $BUILD_DIR
  DEPS_DIR ............................. $DEPS_DIR
  COOT_DOWNLOAD_DIR .................... $COOT_DOWNLOAD_DIR
  COOT_BUILD_DIR ....................... $COOT_BUILD_DIR
  CARGO_HOME ........................... $CARGO_HOME

e

# -------------------------------------------------------------------------------------
# figure out usable compiler version:
for __v in 13 12 11
do
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
[ "X$GCC_COMPILER_VERSION" = "X" ] && error "no working (?) gcc/g++ version 13/12/11 found?"
printf "\n ### Compiler version found/used = $GCC_COMPILER_VERSION\n\n"

# -------------------------------------------------------------------------------------
# generic build functions:
build_with_meson () {
  __p=$1;shift
  __v=$1;shift
  if [ ! -f $BUILD_DIR/$__p/.my_done${MY_DONE_EXT} ]; then
    printf " ### building $__p ($__v) with meson\n"
    mkdir -p $BUILD_DIR/$__p || error
    cd $BUILD_DIR/$__p || error
    rm -rf *
    pushd $DEPS_DIR/${__p}-${__v} >/dev/null || error
    printf "  meson setup (see `pwd`/my_meson_setup.log${MY_DONE_EXT}) ... "
    meson setup --prefix=$PREFIX $@ $BUILD_DIR/${__p} > my_meson_setup.log${MY_DONE_EXT} 2>&1 || error "see `pwd`/my_meson_setup.log${MY_DONE_EXT}"
    echo "done"
    popd > /dev/null || error
    printf "  meson compile (see `pwd`/my_meson_compile.log${MY_DONE_EXT}) ... "
    meson compile > my_meson_compile.log${MY_DONE_EXT} 2>&1 || error "see `pwd`/my_meson_compile.log${MY_DONE_EXT}"
    echo "done"
    printf "  meson install (see `pwd`/my_meson_install.log${MY_DONE_EXT}) ... "
    meson install > my_meson_install.log${MY_DONE_EXT} 2>&1 || error "see `pwd`/my_meson_install.log${MY_DONE_EXT}"
    echo "done"
    cd .. || error
    touch $BUILD_DIR/$__p/.my_done${MY_DONE_EXT}
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
  if [ ! -f $BUILD_DIR/$__p/.my_done${MY_DONE_EXT} ]; then
    printf " ### building $__p ($__v) with configure/make\n"
    mkdir -p $BUILD_DIR/$__p || error
    cd $BUILD_DIR/$__p || error
    rm -rf *
    if [ $__do_autogen -eq 1 ]; then
      printf "  autogen.sh (see `pwd`/my_autogen.log${MY_DONE_EXT}) ... "
      $DEPS_DIR/${__p}-${__v}/autogen.sh --prefix=$PREFIX > my_autogen.log${MY_DONE_EXT} 2>&1 || error "see `pwd`/my_autogen.log${MY_DONE_EXT}"
      echo "done"
    fi
    printf "  configure (see `pwd`/my_configure.log${MY_DONE_EXT}) ... "
    $DEPS_DIR/${__p}-${__v}/configure --prefix=$PREFIX $@ > my_configure.log${MY_DONE_EXT} 2>&1 || error "see `pwd`/my_configure.log${MY_DONE_EXT}"
    echo "done"
    printf "  make (see `pwd`/my_make.log${MY_DONE_EXT}) ... "
    make -j ${nthreads} > my_make.log${MY_DONE_EXT} 2>&1 || error "see `pwd`/my_make.log${MY_DONE_EXT}"
    echo "done"
    printf "  make install (see `pwd`/my_make_install.log${MY_DONE_EXT}) ... "
    make install > my_make_install.log${MY_DONE_EXT} 2>&1 || error "see `pwd`/my_make_install.log${MY_DONE_EXT}"
    echo "done"
    cd .. || error
    touch $BUILD_DIR/$__p/.my_done${MY_DONE_EXT}
  fi
}
build_with_cmake () {
  __p=$1;shift
  __v=$1;shift
  if [ ! -f $BUILD_DIR/$__p/.my_done${MY_DONE_EXT} ]; then
    printf " ### building $__p ($__v) with cmake\n"
    mkdir -p $BUILD_DIR/$__p || error
    cd $BUILD_DIR/$__p || error
    rm -rf *
    printf "  cmake (see `pwd`/my_cmake.log${MY_DONE_EXT}) ... "
    cmake $DEPS_DIR/${__p}-${__v} \
          -DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_BUILD_TYPE=release $@ > my_cmake.log${MY_DONE_EXT} 2>&1 || error "see `pwd`/my_cmake.log${MY_DONE_EXT}"
    echo "done"
    printf "  cmake --build (see `pwd`/my_cmake_build.log${MY_DONE_EXT}) ... "
    cmake --build . > my_cmake_build.log${MY_DONE_EXT} 2>&1 || error "see `pwd`/my_cmake_build.log${MY_DONE_EXT}"
    echo "done"
    printf "  cmake --install (see `pwd`/my_cmake_install.log${MY_DONE_EXT}) ... "
    cmake --install .  > my_cmake_install.log${MY_DONE_EXT} 2>&1 || error "see `pwd`/my_cmake_install.log${MY_DONE_EXT}"
    echo "done"
    cd .. || error
    touch $BUILD_DIR/$__p/.my_done${MY_DONE_EXT}
  fi
}

# -------------------------------------------------------------------------------------
# specific build functions

build_python() {
  build_with_configure python ${PYTHON_VER} --libdir=$PREFIX/lib --enable-optimizations --with-system-expat=true --with-lto=full \
  --without-static-libpython --enable-shared
}

build_libjpeg() {
  build_with_cmake libjpeg-turbo ${LIBJPEG_VER} \
    -DCMAKE_INSTALL_LIBDIR=$PREFIX/lib \
    -DENABLE_STATIC=OFF \
    -DWITH_JAVA=OFF
}

build_libunistring() {
  build_with_configure libunistring ${LIBUNISTRING_VER}
}
build_gc() {
  build_with_configure gc ${GC_VER}
}
build_glm() {
  build_with_cmake glm ${GLM_VER}
}
build_pcre2() {
  build_with_cmake pcre2 ${PCRE2_VER} -DPCRE2_STATIC_PIC=ON
}

# see https://docs.gtk.org/glib/building.html
build_glib() {
  build_with_meson glib ${GLIB_VER} -Dintrospection=disabled
}
build_glib2() {
  build_with_meson glib ${GLIB_VER} -Dintrospection=enabled
}

build_gobject_introspection() {
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

build_guile() {
  build_with_configure guile ${GUILE_VER} --enable-shared --disable-static --disable-error-on-warning --enable-mini-gmp
}

build_swig() {
  build_with_configure swig ${SWIG_VER}
}

build_boost() {
  if [ ! -f $BUILD_DIR/boost/.my_done${MY_DONE_EXT} ]; then
    rm -rf $BUILD_DIR/boost
    cp -a $DEPS_DIR/boost_${BOOST_VER_} $BUILD_DIR/boost || error
    cd $BUILD_DIR/boost || error

    printf "   bootstrapping boost (see `pwd`/my_bootstrap.log${MY_DONE_EXT}) ... "
    ./bootstrap.sh --with-toolset=gcc${GCC_COMMAND_EXT} --with-libraries=serialization,regex,chrono,date_time,filesystem,iostreams,program_options,thread,math,random,system,atomic,container,context,fiber,coroutine,json,python,random > my_bootstrap.log${MY_DONE_EXT} 2>&1 || error "see `pwd`/my_bootstrap.log${MY_DONE_EXT}"
    echo "done"

    if [ "X${GCC_COMMAND_EXT}" != "X" ]; then
      echo "using gcc : ${GCC_COMPILER_VERSION} : /usr/bin/g++${GCC_COMMAND_EXT} ; " >> user-config.jam || error "see above and `pwd`/user-config.jam"
      sed -i "s/gcc${GCC_COMMAND_EXT}/gcc/g" project-config.jam || error
    fi

    printf "   building boost (see `pwd`/my_build.log${MY_DONE_EXT}) ... "
    BOOST_BUILD_PATH=. ./b2 link=shared variant=release threading=multi runtime-link=shared install --prefix=${PREFIX} > my_build.log${MY_DONE_EXT} 2>&1 || error "see `pwd`/my_build.log${MY_DONE_EXT}"
    echo "done"

    cd .. || error
    touch $BUILD_DIR/boost/.my_done${MY_DONE_EXT}
  fi
}

build_libepoxy() {
  build_with_meson libepoxy ${LIBEPOXY_VER}
}

# not sure if we really need to build harfbuzz twice ...
build_harfbuzz() {
  build_with_meson harfbuzz ${HARFBUZZ_VER} -Dtests=disabled
}
build_harfbuzz2() {
  build_with_meson harfbuzz ${HARFBUZZ_VER} -Dtests=disabled
}

build_graphene() {
  build_with_meson graphene ${GRAPHENE_VER}
}

build_freetype() {
  build_with_cmake freetype ${FREETYPE_VER} -DBUILD_SHARED_LIBS=true
}

build_fontconfig() {
  build_with_meson fontconfig ${FONTCONFIG_VER}
}

build_pixman() {
  build_with_meson pixman ${PIXMAN_VER}
}

build_poppler() {
  build_with_cmake poppler ${POPPLER_VER} -DENABLE_NSS3=OFF \
  -DENABLE_GPGME=OFF -DBUILD_GTK_TESTS=OFF -DBUILD_QT5_TESTS=OFF \
  -DBUILD_QT6_TESTS=OFF -DENABLE_BOOST=ON -DENABLE_QT5=OFF -DENABLE_QT6=OFF \
  -DENABLE_LIBOPENJPEG=none -DENABLE_LCMS=OFF -DENABLE_LIBCURL=ON -DENABLE_DCTDECODER=libjpeg
}

build_tiff() {
  if [ ! -f $BUILD_DIR/libtiff/.my_done${MY_DONE_EXT} ]; then
    rm -rf $BUILD_DIR/libtiff
    cp -a $DEPS_DIR/libtiff-v${LIBTIFF_VER}/ $BUILD_DIR/libtiff || error
    cd $BUILD_DIR/libtiff || error

    printf "   running autogen (see `pwd`/my_autogen.log${MY_DONE_EXT}) ... "
    ./autogen.sh --prefix=$PREFIX > my_autogen.log${MY_DONE_EXT} 2>&1 || error "see `pwd`/my_autogen.log${MY_DONE_EXT}"
    echo "done"

    printf "   running configure (see `pwd`/my_configure.log${MY_DONE_EXT}) ... "
    ./configure --prefix=$PREFIX \
                --enable-cxx \
                --with-jpeg-lib-dir=$PREFIX/lib \
                --with-jpeg-include-dir=$PREFIX/include > my_configure.log${MY_DONE_EXT} 2>&1 || error "see `pwd`/my_configure.log${MY_DONE_EXT}"
    echo "done"

    printf "   running make (see `pwd`/my_make.log${MY_DONE_EXT}) ... "
    make -j ${nthreads} > my_make.log${MY_DONE_EXT} 2>&1 || error "see `pwd`/my_make.log${MY_DONE_EXT}"
    echo "done"

    printf "   running install (see `pwd`/my_make_install.log${MY_DONE_EXT}) ... "
    make install > my_make_install.log${MY_DONE_EXT} 2>&1 || error "see `pwd`/my_make_install.log${MY_DONE_EXT}"
    echo "done"

    cd .. || error
    touch $BUILD_DIR/libtiff/.my_done${MY_DONE_EXT}
  fi
}

# not sure if we really need to build twice ...
build_cairo() {
  build_with_meson cairo ${CAIRO_VER} --wrap-mode=nodownload -Dtests=disabled
}
build_cairo2() {
  build_with_meson cairo ${CAIRO_VER} --wrap-mode=nodownload -Dtests=disabled
}

build_pango() {
  build_with_meson pango ${PANGO_VER}
}

build_smi() {
  build_with_meson shared-mime-info ${SMI_VER}
}

build_librsvg() {
  build_with_autogen_and_configure librsvg ${LIBRSVG_VER}
}

# not sure if we really need to build twice ...
build_gdk_pixbuf() {
  build_with_meson gdk-pixbuf ${GDK_PIXBUF_VER} -Dtests=false -Dman=false -Dgtk_doc=false
}
build_gdk_pixbuf2() {
  build_with_meson gdk-pixbuf ${GDK_PIXBUF_VER} -Dtests=false -Dman=false -Dgtk_doc=false
}

build_atk() {
  build_with_meson atk ${ATK_VER}
}

build_wayland() {
  build_with_meson wayland ${WAYLAND_VER} -Dtests=false -Ddocumentation=false
}

build_gtk() {
  build_with_meson gtk ${GTK_VER} -Dbroadway-backend=true -Dwin32-backend=false -Dmacos-backend=false \
    -Dmedia-gstreamer=disabled  -Dintrospection=enabled -Dvulkan=disabled -Dbuild-tests=false \
    -Dbuild-testsuite=false -Dbuild-examples=false -Dbuild-demos=false -Dprint-cups=disabled
}


build_pygobject() {
  build_with_meson pygobject ${PYGOBJECT_VER}
}

 
build_rdkit() {
  build_with_cmake rdkit ${RDKIT_VER} -DRDK_BUILD_CAIRO_SUPPORT=ON \
  -DRDK_BUILD_INCHI_SUPPORT=OFF \
  -DRDK_INSTALL_COMIC_FONTS=OFF \
  -DRDK_INSTALL_INTREE=OFF
}

build_mmdb2() {
  build_with_configure mmdb2 ${MMDB_VER} --enable-shared
}


build_gsl() {
  build_with_configure gsl ${GSL_VER}
}

build_gemmi() {
  build_with_cmake gemmi ${GEMMI_VER} -DBUILD_SHARED_LIBS=true
}

build_libccp4() {
  additional_build_env_setup
  build_with_configure libccp4 ${LIBCCP4_VER} \
    --enable-shared --disable-static \
    --datadir=$PREFIX/share/ccp4
}

build_libssm() {
  additional_build_env_setup
  if [ ! -f $BUILD_DIR/libssm/.my_done${MY_DONE_EXT} ]; then
    rm -rf $BUILD_DIR/libssm
    cp -a $DEPS_DIR/libssm-${LIBSSM_VER} $BUILD_DIR/libssm || error
    cd $BUILD_DIR/libssm || error

    printf "   setting up libssm ... "
    ( aclocal && libtoolize --automake --copy && autoconf && automake --copy --add-missing --gnu ) > my_setup.log${MY_DONE_EXT} 2>&1 || error "see `pwd`/my_setup.log${MY_DONE_EXT}"
    echo "done"

    printf "   configure libssm ... "
    ./configure --prefix=$PREFIX \
      --enable-shared --disable-static \
      --enable-ccp4 > my_configure.log${MY_DONE_EXT} 2>&1 || error "see `pwd`/my_configure.log${MY_DONE_EXT}"
      # unrecognized option
      #--with-mmdb=$PREFIX \
    echo "done"

    printf "   making libssm ... "
    make -j ${nthreads} > my_make.log${MY_DONE_EXT} 2>&1 || error "see `pwd`/my_make.log${MY_DONE_EXT}"
    echo "done"

    printf "   installing libssm ... "
    make install > my_make_install.log${MY_DONE_EXT} 2>&1 || error "see `pwd`/my_make_install.log${MY_DONE_EXT}"
    echo "done"

    cd .. || error
    touch $BUILD_DIR/libssm/.my_done${MY_DONE_EXT}
  fi
}

build_libclipper() {
  additional_build_env_setup
  if [ ! -f $BUILD_DIR/libclipper/.my_done${MY_DONE_EXT} ]; then
    mkdir -p $BUILD_DIR/libclipper || error
    cd $BUILD_DIR/libclipper || error
    rm -rf *

    printf "   configure clipper with FC=$FC CC=$CC CXX=$CXX ... "
    $DEPS_DIR/clipper-${LIBCLIPPER_VER_PRE}/configure --prefix=$PREFIX \
      --enable-shared --disable-static \
      --enable-contrib --enable-ccp4 \
      --enable-cif --enable-mmdb --enable-minimol \
      --enable-cns --enable-phs --enable-fortran > my_configure.log${MY_DONE_EXT} 2>&1 || error "see `pwd`/my_configure.log${MY_DONE_EXT}"
    echo "done"

    printf "   make clipper ... "
    make -j ${nthreads} > my_make.log${MY_DONE_EXT} 2>&1 || error "see `pwd`/my_make.log${MY_DONE_EXT}"
    echo "done"

    printf "   installing clipper ... "
    make install > my_make_install.log${MY_DONE_EXT} 2>&1 || error "see `pwd`/my_make_install.log${MY_DONE_EXT}"
    echo "done"
    
    cd .. || error
    touch $BUILD_DIR/libclipper/.my_done${MY_DONE_EXT}
  fi
}

build_fftw() {  
  FFTW_CONFIGURE="./configure F77=gfortran${GCC_COMMAND_EXT} --prefix=$PREFIX   --enable-shared --disable-static  --enable-openmp --enable-threads --with-gcc --with-gcc-ld"
  if [ ! -f $BUILD_DIR/fftw/.my_done${MY_DONE_EXT} ]; then
    rm -rf $BUILD_DIR/fftw
    cp -a $DEPS_DIR/fftw-${FFTW_VER} $BUILD_DIR/fftw || error
    cd $BUILD_DIR/fftw || error
    ${FFTW_CONFIGURE} > my_configure.log${MY_DONE_EXT} 2>&1 || error "see `pwd`/my_configure.log${MY_DONE_EXT}"
    make -j ${nthreads} > my_make.log${MY_DONE_EXT} 2>&1 || error "see `pwd`/my_make.log${MY_DONE_EXT}"
    make install > my_make_install.log${MY_DONE_EXT} 2>&1 || error "see `pwd`/my_make_install.log${MY_DONE_EXT}"
    cd .. || error
    touch $BUILD_DIR/fftw/.my_done${MY_DONE_EXT}
  fi

  if [ ! -f $BUILD_DIR/sfftw/.my_done${MY_DONE_EXT} ]; then
    rm -rf $BUILD_DIR/sfftw
    cp -a $DEPS_DIR/fftw-${FFTW_VER} $BUILD_DIR/sfftw || error
    cd $BUILD_DIR/sfftw || error
    ${FFTW_CONFIGURE} --enable-type-prefix --enable-float > my_configure.log${MY_DONE_EXT} 2>&1 || error "see `pwd`/my_configure.log${MY_DONE_EXT}"
    make -j ${nthreads} > my_make.log${MY_DONE_EXT} 2>&1 || error "see `pwd`/my_make.log${MY_DONE_EXT}"
    make install > my_make_install.log${MY_DONE_EXT} 2>&1 || error "see `pwd`/my_make_install.log${MY_DONE_EXT}"
    cd .. || error
    touch $BUILD_DIR/sfftw/.my_done${MY_DONE_EXT}
  fi
}

# -------------------------------------------------------------------------------------
# other functions
do_wget() {
  __url=$1;shift
  if [ $# -eq 1 ]; then
    __out=$1
  else
    __out=`basename $__url`
  fi
  if [ ! -f $__out ]; then
    printf "\n getting $__out ... "
    wget -q --retry-connrefused --waitretry=1 --read-timeout=10 --timeout=10 -t 15 -O "$__out" "$__url" || error
    echo "done"
    case "$__out" in
      *.tar*|*.tgz)
        printf "   unpacking $__out ... "
        tar -xf "$__out" || error
        echo "done"
        ;;
    esac
  fi
}

initial_setup() {
  
  mkdir -p $PREFIX    || error
  mkdir -p $DEPS_DIR  || error
  mkdir -p $BUILD_DIR || error

#  install_dependencies_with_distro_package_manager
  
  # Some distros ship ancient python. We need a fairly new version of pip and python.
  pushd $DEPS_DIR > /dev/null || error
  do_wget https://www.python.org/ftp/python/${PYTHON_VER}/Python-${PYTHON_VER}.tar.xz
  if [ -d Python-${PYTHON_VER} ] && [ ! -d python-${PYTHON_VER} ]; then
    mv Python-${PYTHON_VER} python-${PYTHON_VER} || error
  fi
  popd >/dev/null || error

  if [ ! -x $PREFIX/bin/python3 ]; then
    build_python || error
    # For Boost.Python to build
    ln -sf $PREFIX/bin/python3 $PREFIX/bin/python
    ln -sf $PREFIX/bin/pip3 $PREFIX/bin/pip
  fi

  if [ ! -f .my_pip_install_done ]; then
    printf "\n pip installing meson et al (see `pwd`/my_pip_install.log) ... "
    python3 -m pip install meson setuptools numpy packaging requests xattr > my_pip_install.log 2>&1 || error "see `pwd`/my_pip_install.log"
    echo "done"
    touch .my_pip_install_done
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
    ./bootstrap --prefix=$PREFIX > my_bootstrap.log 2>&1 || error "see `pwd`/my_bootstrap.log"
    echo "done"

    printf "   building CMake ... "
    make -j ${nthreads} > my_make.log 2>&1 || error "see `pwd`/my_make.log"
    echo "done"

    printf "   installing CMake ... "
    make install > my_make_install.log 2>&1 || error "see `pwd`/my_make_install.log"
    echo "done"
    
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
    cmake -Bbuild-cmake -DCMAKE_INSTALL_PREFIX=$PREFIX > my_cmake.log 2>&1 || error "see `pwd`/my_cmake.log"
    echo "done"

    printf "   running build ... "
    cmake --build build-cmake > my_cmake_build.log 2>&1 || error "see `pwd`/my_cmake_build.log"
    echo "done"

    printf "   running install ... "
    cmake --install build-cmake > my_cmake_install.log 2>&1 || error "see `pwd`/my_cmake_install.log"
    echo "done"
    
    cd ${PREFIX} || error
    touch $BUILD_DIR/ninjabuild/.my_done
  fi

  cd $PREFIX || error
  if [ ! -f rustup-init.sh ]; then
    printf "\n### Installing RUST (hopefully into CARGO_HOME=$CARGO_HOME)\n"
    # Rust for librsvg - installs into $HOME it seems?!
    do_wget https://sh.rustup.rs rustup-init.sh || error
    chmod +x rustup-init.sh || error
    RUSTUP_INIT_SKIP_PATH_CHECK=yes ./rustup-init.sh --profile default -y --no-modify-path > my_rust_install.log 2>&1 || error "see `pwd`/my_rust_install.log"
  fi
}

setup_build_env() {
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
  export CC=gcc${GCC_COMMAND_EXT}
  type $CC 2>&1 | awk '{print " #",$0}' || error
  export CXX=g++${GCC_COMMAND_EXT}
  type $CXX 2>&1 | awk '{print " #",$0}'  || error
  export FC=gfortran${GCC_COMMAND_EXT}
  type $FC 2>&1 | awk '{print " #",$0}'  || error
  export F77=$FC # for libccp4
  #export FC=gfortran-10
  export PYTHONPATH=$PREFIX/lib64/python${PYTHON_VER_MAJOR}.${PYTHON_VER_MINOR}/lib-dynload
}

additional_build_env_setup() {
  export FFLAGS="-fallow-argument-mismatch"
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

download_dependencies() {
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
    mv gobject-introspection-${GOBJECT_INTROSPECTION_VER} gobject_introspection-${GOBJECT_INTROSPECTION_VER} || error
  fi

  # Guile
  do_wget https://ftp.gnu.org/pub/gnu/guile/guile-${GUILE_VER}.tar.gz

  # SWIG
  do_wget https://downloads.sourceforge.net/swig/swig-${SWIG_VER}.tar.gz
  
  # Boost
  do_wget https://boostorg.jfrog.io/artifactory/main/release/${BOOST_VER}/source/boost_${BOOST_VER_}.tar.bz2

  # Libepoxy
  do_wget https://github.com/anholt/libepoxy/archive/refs/tags/${LIBEPOXY_VER}.tar.gz libepoxy-${LIBEPOXY_VER}.tar.gz

  # Graphene
  do_wget https://github.com/ebassi/graphene/archive/refs/tags/${GRAPHENE_VER}.tar.gz graphene-${GRAPHENE_VER}.tar.gz

  # Harfbuzz
  do_wget https://github.com/harfbuzz/harfbuzz/archive/refs/tags/${HARFBUZZ_VER}.tar.gz harfbuzz-${HARFBUZZ_VER}.tar.gz

  # Freetype2
  do_wget https://deac-ams.dl.sourceforge.net/project/freetype/freetype2/${FREETYPE_VER}/freetype-${FREETYPE_VER}.tar.xz
  
  # Fontconfig
  do_wget  https://www.freedesktop.org/software/fontconfig/release/fontconfig-${FONTCONFIG_VER}.tar.xz

  # Pixman
  do_wget https://www.cairographics.org/releases/pixman-${PIXMAN_VER}.tar.gz

  # Libtiff
  do_wget https://gitlab.com/libtiff/libtiff/-/archive/v${LIBTIFF_VER}/libtiff-v${LIBTIFF_VER}.tar.gz

  # Poppler
  do_wget https://poppler.freedesktop.org/poppler-${POPPLER_VER}.tar.xz
  
  # Cairo
  do_wget https://cairographics.org/releases/cairo-${CAIRO_VER}.tar.xz

  # Pango
  do_wget https://download.gnome.org/sources/pango/${PANGO_VER_MM}/pango-${PANGO_VER}.tar.xz

  # Shared-mime-info
  do_wget https://gitlab.freedesktop.org/xdg/shared-mime-info/-/archive/${SMI_VER}/shared-mime-info-${SMI_VER}.tar.gz

  # Librsvg
  do_wget https://gitlab.gnome.org/GNOME/librsvg/-/archive/${LIBRSVG_VER}/librsvg-${LIBRSVG_VER}.tar.gz

  # GDK-Pixbuf
  do_wget https://download.gnome.org/sources/gdk-pixbuf/${GDK_PIXBUF_VER_MM}/gdk-pixbuf-${GDK_PIXBUF_VER}.tar.xz

  # Atk
  do_wget https://download.gnome.org/sources/atk/${ATK_VER_MM}/atk-${ATK_VER}.tar.xz

  # Wayland
  do_wget https://gitlab.freedesktop.org/wayland/wayland/-/archive/${WAYLAND_VER}/wayland-${WAYLAND_VER}.tar.gz

  # Gtk
  do_wget https://download.gnome.org/sources/gtk/${GTK_VER_Major}.${GTK_VER_Minor}/gtk-${GTK_VER}.tar.xz

  # PyGObject
  do_wget https://github.com/GNOME/pygobject/archive/refs/tags/${PYGOBJECT_VER}.tar.gz pygobject-${PYGOBJECT_VER}.tar.gz

  # RDKit
  do_wget https://github.com/rdkit/rdkit/archive/refs/tags/Release_${RDKIT_VER}.tar.gz
  if [ -d rdkit-Release_${RDKIT_VER} ] && [ ! -d rdkit-${RDKIT_VER} ]; then
    mv rdkit-Release_${RDKIT_VER} rdkit-${RDKIT_VER} || error
  fi

  # MMDB
  do_wget https://www2.mrc-lmb.cam.ac.uk/personal/pemsley/coot/dependencies/mmdb2-${MMDB_VER}.tar.gz

  # GSL
  do_wget https://ftp.gnu.org/gnu/gsl/gsl-${GSL_VER}.tar.gz

  # GEMMI
  do_wget https://github.com/project-gemmi/gemmi/archive/refs/tags/v${GEMMI_VER}.tar.gz gemmi-${GEMMI_VER}.tar.gz

  # Libccp4
  do_wget https://www2.mrc-lmb.cam.ac.uk/personal/pemsley/coot/dependencies/libccp4-${LIBCCP4_VER}.tar.gz

  # Libssm
  do_wget https://www2.mrc-lmb.cam.ac.uk/personal/pemsley/coot/dependencies/ssm-${LIBSSM_VER}.tar.gz libssm-${LIBSSM_VER}.tar.gz
  if [ -d ssm-${LIBSSM_VER} ] && [ ! -d libssm-${LIBSSM_VER} ]; then
    mv ssm-${LIBSSM_VER} libssm-${LIBSSM_VER} || error
  fi

  ## This is some patch from the AUR. I don't know what it fixes
  ## But I guess we need it
  do_wget "https://aur.archlinux.org/cgit/aur.git/plain/ssm.pc.in?h=libssm" ssm.pc.in
  cp -p ssm.pc.in libssm-${LIBSSM_VER}/ssm.pc.in || error

  # Libclipper
  do_wget https://www2.mrc-lmb.cam.ac.uk/personal/pemsley/coot/dependencies/clipper-${LIBCLIPPER_VER}.tar.gz libclipper-${LIBCLIPPER_VER}.tar.gz

  # FFTW
  do_wget http://www.fftw.org/fftw-${FFTW_VER}.tar.gz

  # libunistring
  do_wget https://ftp.gnu.org/gnu/libunistring/libunistring-${LIBUNISTRING_VER}.tar.gz

  # gc
  do_wget https://www.hboehm.info/gc/gc_source/gc-${GC_VER}.tar.gz

  # glm
  do_wget https://github.com/g-truc/glm/archive/refs/tags/${GLM_VER}.tar.gz glm-${GLM_VER}.tar.gz

  # pcre2
  do_wget https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${PCRE2_VER}/pcre2-${PCRE2_VER}.tar.gz
}

build_dependencies() {
  # order matters - and some have to be done multiple times it seems
  __ps="glib gobject_introspection libunistring gc glm pcre2 guile swig libepoxy boost
  gobject_introspection glib gobject_introspection graphene harfbuzz
  freetype fontconfig libjpeg pixman cairo gobject_introspection
  harfbuzz pango smi gdk_pixbuf librsvg tiff poppler cairo gdk_pixbuf
  atk wayland gtk pygobject fftw rdkit mmdb2 gsl gemmi libccp4 libssm
  libclipper"

  __ps="glib gobject_introspection libunistring gc glm pcre2 guile swig libepoxy boost
        glib graphene harfbuzz freetype fontconfig libjpeg pixman cairo harfbuzz pango
        smi gdk_pixbuf librsvg tiff poppler cairo gdk_pixbuf
        atk wayland gtk pygobject fftw rdkit mmdb2 gsl gemmi libccp4 libssm
        libclipper"
  for __p in $__ps
  do
    __pp=`echo $__p | sed "s/-//g"`
    eval "__n=\$__n_${__pp}"
    [ "X$__n" = "X" ] && __n=0
    __n=`expr $__n + 1`
    case $__n in
      1) __t="";;
      *) __t=" again (#$__n)";export MY_DONE_EXT=$__n;;
    esac
    printf "\n >>> building $__p${__t}\n"
    eval "build_${__p}${__n#1}" || error
    eval "__n_${__pp}=\$__n"
    unset MY_DONE_EXT
  done
}

download_coot() {
  cd $COOT_DOWNLOAD_DIR
  if [ ! -d coot ]; then
    printf " ### Coot: git clone (see `pwd`/my_git_clone.log) ... "
    git clone --depth 2 https://github.com/hgonomeg/coot.git > my_git_clone.log 2>&1 || error "see `pwd`/my_git_clone.log"
    echo "done"
  fi
}

build_coot() {
  cd $COOT_BUILD_DIR
  additional_build_env_setup
  if [ ! -f .my_autogen_done ]; then
    printf " ### Coot: autogen.sh (see `pwd`/my_autogen.log) ... "
    ./autogen.sh > my_autogen.log 2>&1 || error "see `pwd`/my_autogen.log"
    echo "done"
    touch .my_autogen_done
  fi
  #--with-libdw --with-backward
  if [ ! -f .my_configure_done ]; then
    printf " ### Coot: configure (see `pwd`/my_configure.log) ... "
    SHELL=/bin/bash \
    PYTHON=python3 \
    CXXFLAGS="${CXXFLAGS} -ggdb -O2 -march=native -Wreturn-type -Wl,--as-needed -Wno-sequence-point -Wsign-compare -Wno-unknown-pragmas" \
    ./configure --prefix=$PREFIX \
                --libexecdir=$PREFIX/libexec \
                --disable-static \
                --with-enhanced-ligand-tools \
                --with-rdkit-prefix=$PREFIX \
                --with-boost=$PREFIX \
                --with-gemmi=$PREFIX \
                --with-boost-thread=boost_thread \
                --with-boost-python="boost_python${PYTHON_VER_MAJOR}${PYTHON_VER_MINOR}" \
                > my_configure.log 2>&1 || error "see `pwd`/my_configure.log"
    echo "done"
    touch .my_configure_done
  fi
  if [ ! -f .my_make_done ]; then
    sed -i "`grep -n \"BOOST_CPPFLAGS =\" $COOT_BUILD_DIR/pyrogen/Makefile | cut -f1 -d:`s/-pthread//" $COOT_BUILD_DIR/pyrogen/Makefile || error
    printf " ### Coot: make (see `pwd`/my_make.log) ... "
    make -j ${nthreads} > my_make.log 2>&1 || error "see `pwd`/my_make.log"
    echo "done"
    printf " ### Coot: make (see `pwd`/my_make_install.log) ... "
    make install > my_make_install.log 2>&1 || error "see `pwd`/my_make_install.log"
    echo "done"
    touch .my_make_done
  fi
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
  printf "\n packaging Coot as $out ... "
  tar -czf $out bin/coot* bin/layla bin/pyrogen bin/find* bin/mmrrcc lib lib64 libexec share > my_tar.log 2>&1 || error "see `pwd`/my_tar.log"
  echo "done"
  printf "\n"
  ls -l $out
  printf "\n"
}

setup_all_and_build_coot() {
  setup_build_env
  initial_setup
  download_dependencies
  build_dependencies
  cat <<e

########################################################################
### Now for the real thing: Coot
########################################################################

e
  download_coot
  build_coot
}

setup_all_and_build_coot
package_coot
