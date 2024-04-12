#!/usr/bin/bash
# This script is meant to run on docker image
# together with the adequate distro-specific configuration (sourced_below)

CMAKE_VER=3.29.1
NINJA_VER=1.11.1
PYTHON_VER_MAJOR=3
# Todo: bring back Python 3.12 when Coot drops usage of the `imp` module
#PYTHON_VER_MINOR=12
#PYTHON_VER_PATCH=2
PYTHON_VER_MINOR=11
PYTHON_VER_PATCH=8
PYTHON_VER="${PYTHON_VER_MAJOR}.${PYTHON_VER_MINOR}.${PYTHON_VER_PATCH}"

export PREFIX=/pfx
export BUILD_DIR=/build
export DEPS_DIR=/deps
export COOT_DOWNLOAD_DIR=$PREFIX
export COOT_BUILD_DIR=$COOT_DOWNLOAD_DIR/coot

# Load the Docker-image-specific variables and functions
source /dl_and_build_coot.image-specific.sh


build_python() {
  setup_build_env
  mkdir -p $BUILD_DIR/python
  cd $BUILD_DIR/python &&\
  rm -rf *
  $DEPS_DIR/Python-${PYTHON_VER}/configure --prefix=$PREFIX --enable-optimizations --with-system-expat=true --with-lto=full \
  --without-static-libpython --enable-shared
  make -j `nproc --all` && make install
  cd ..
}

do_wget() {
  wget --retry-connrefused --waitretry=1 --read-timeout=10 --timeout=10 -t 15 "$@" || exit 7
}

initial_setup() {
  
  mkdir $PREFIX
  mkdir $DEPS_DIR
  mkdir $BUILD_DIR

  install_dependencies_with_distro_package_manager
  
  # Some distros ship ancient python. We need a fairly new version of pip and python.
  pushd $DEPS_DIR
  do_wget https://www.python.org/ftp/python/${PYTHON_VER}/Python-${PYTHON_VER}.tar.xz &&\
  tar -xf Python-${PYTHON_VER}.tar.xz
  popd
  
  build_python
  # For Boost.Python to build
  ln -s $PREFIX/bin/python3 $PREFIX/bin/python

  setup_build_env
  python3 -m pip install meson setuptools numpy packaging requests xattr
  # python3 -m pip install meson numpy

  # Newer CMake
  mkdir $BUILD_DIR/cmakebuild
  cd $BUILD_DIR/cmakebuild
  do_wget https://github.com/Kitware/CMake/archive/refs/tags/v${CMAKE_VER}.tar.gz &&\
  tar -xf v${CMAKE_VER}.tar.gz &&\
  cd CMake-${CMAKE_VER} &&\
  ./bootstrap --prefix=$PREFIX && make -j `nproc --all` && make install &&\
  cd ${HOME} &&\
  rm -rf $BUILD_DIR/cmakebuild

  #Newer Ninja
  mkdir $BUILD_DIR/ninjabuild
  cd $BUILD_DIR/ninjabuild
  do_wget https://github.com/ninja-build/ninja/archive/refs/tags/v${NINJA_VER}.tar.gz &&\
  tar -xf v${NINJA_VER}.tar.gz &&\
  cd ninja-${NINJA_VER} &&\
  cmake -Bbuild-cmake -DCMAKE_INSTALL_PREFIX=$PREFIX &&\
  cmake --build build-cmake &&\
  cmake --install build-cmake &&\
  cd ${HOME} &&\
  rm -rf $BUILD_DIR/ninjabuild

  #Rust for librsvg
  do_wget https://sh.rustup.rs -O rustup-init.sh
  chmod +x rustup-init.sh
  ./rustup-init.sh --profile default -y --no-modify-path
  rm rustup-init.sh
  
  
}

setup_build_env() {
  export PKG_CONFIG_LIBDIR=$PREFIX/lib/x86_64-linux-gnu/:$PREFIX/lib64:$PREFIX/lib:/usr/lib/x86_64-linux-gnu:/usr/lib64:/usr/lib
  export PKG_CONFIG_PATH=$PREFIX/lib/x86_64-linux-gnu/pkgconfig:$PREFIX/lib64/pkgconfig:$PREFIX/lib/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:$PREFIX/share/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig
  export PATH="$HOME/.cargo/bin:$PREFIX/bin:$PATH"
  export LD_LIBRARY_PATH="$PREFIX/lib/x86_64-linux-gnu/:$PREFIX/lib64:$PREFIX/lib"
  export ACLOCAL_PATH="$PREFIX/share/aclocal"
  export CMAKE_PREFIX_PATH="$PREFIX"
  export GI_TYPELIB_PATH="$PREFIX/lib/girepository-1.0:$PREFIX/lib64/girepository-1.0"
  export CMAKE_BUILD_PARALLEL_LEVEL=`nproc --all`
  # GCC_COMPILER_VERSION is defined in image-specific configuration, sourced above
  export CC=gcc-${GCC_COMPILER_VERSION}
  export CXX=g++-${GCC_COMPILER_VERSION}
  export FC=gfortran-${GCC_COMPILER_VERSION}
  #export F77=$FC
  #export FC=gfortran-10
}

additional_build_env_setup() {
  export CFLAGS="-I${PREFIX}/include"
  export CXXFLAGS="-I${PREFIX}/include"
  IFS=":"
  for i in $PKG_CONFIG_LIBDIR; do
      export LDFLAGS="-L${i} ${LDFLAGS}"
  done
  unset IFS
}

GLIB_VER=2.80.0
GOBJECT_INTROSPECTION_VER_MM=1.80
GOBJECT_INTROSPECTION_VER=${GOBJECT_INTROSPECTION_VER_MM}.1
GUILE_VER=3.0.9
SWIG_VER=4.1.1
BOOST_VER=1.84.0
BOOST_VER_=$(echo $BOOST_VER | tr . _)
LIBEPOXY_VER=1.5.10
GRAPHENE_VER=1.10.8
HARFBUZZ_VER=8.4.0
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
GDK_PIXBUF_VER=${GDK_PIXBUF_VER_MM}.10
ATK_VER_MM=2.38
ATK_VER=${ATK_VER_MM}.0
WAYLAND_VER=1.22.0
GTK_VER_Major=4
GTK_VER_Minor=14
GTK_VER_Patch=2
GTK_VER=${GTK_VER_Major}.${GTK_VER_Minor}.${GTK_VER_Patch}
PYGOBJECT_VER=3.46.0
RDKIT_VER=2023_09_3
MMDB_VER=2.0.22
GSL_VER=2.7.1
GEMMI_VER=0.6.3
LIBCCP4_VER=6.5.1
LIBSSM_VER=1.4
LIBCLIPPER_VER_PRE=2.1
LIBCLIPPER_VER_PATCH=20180802
LIBCLIPPER_VER=${LIBCLIPPER_VER_PRE}.${LIBCLIPPER_VER_PATCH}
FFTW_VER=2.1.5

#TODO:
# * JPEG for poppler (and tiff)
# * curl, libbackward
# * Additional deps: libeigen, coordgen

download_dependencies() {
  setup_build_env
  cd $DEPS_DIR
  
  #Glib
  do_wget https://gitlab.gnome.org/GNOME/glib/-/archive/${GLIB_VER}/glib-${GLIB_VER}.tar.gz &&\
  tar -xf glib-${GLIB_VER}.tar.gz
  # Override glib packaging issue
  rm -rfv glib-${GLIB_VER}/subprojects/gvdb

  #GObject-introspection
  do_wget https://download.gnome.org/sources/gobject-introspection/${GOBJECT_INTROSPECTION_VER_MM}/gobject-introspection-${GOBJECT_INTROSPECTION_VER}.tar.xz &&\
  tar -xf gobject-introspection-${GOBJECT_INTROSPECTION_VER}.tar.xz

  # Guile
  do_wget https://ftp.gnu.org/pub/gnu/guile/guile-${GUILE_VER}.tar.gz &&\
  tar -xf guile-${GUILE_VER}.tar.gz

  # SWIG
  do_wget https://downloads.sourceforge.net/swig/swig-${SWIG_VER}.tar.gz &&\
  tar -xf swig-${SWIG_VER}.tar.gz
  
  #Boost
  do_wget https://boostorg.jfrog.io/artifactory/main/release/${BOOST_VER}/source/boost_${BOOST_VER_}.tar.bz2 &&\
  tar -xf boost_${BOOST_VER_}.tar.bz2

  #Libepoxy
  do_wget https://github.com/anholt/libepoxy/archive/refs/tags/${LIBEPOXY_VER}.tar.gz -O libepoxy-${LIBEPOXY_VER}.tar.gz &&\
  tar -xf libepoxy-${LIBEPOXY_VER}.tar.gz

  #Graphene
  do_wget https://github.com/ebassi/graphene/archive/refs/tags/${GRAPHENE_VER}.tar.gz -O graphene-${GRAPHENE_VER}.tar.gz &&\
  tar -xf graphene-${GRAPHENE_VER}.tar.gz

  #Harfbuzz
  do_wget https://github.com/harfbuzz/harfbuzz/archive/refs/tags/${HARFBUZZ_VER}.tar.gz -O harfbuzz-${HARFBUZZ_VER}.tar.gz &&\
  tar -xf harfbuzz-${HARFBUZZ_VER}.tar.gz

  #Freetype2
  do_wget https://deac-ams.dl.sourceforge.net/project/freetype/freetype2/${FREETYPE_VER}/freetype-${FREETYPE_VER}.tar.xz &&\
  tar -xf freetype-${FREETYPE_VER}.tar.xz
  
  #Fontconfig
  do_wget  https://www.freedesktop.org/software/fontconfig/release/fontconfig-${FONTCONFIG_VER}.tar.xz &&\
  tar -xf fontconfig-${FONTCONFIG_VER}.tar.xz 

  #Pixman
  do_wget https://www.cairographics.org/releases/pixman-${PIXMAN_VER}.tar.gz &&\
  tar -xf pixman-${PIXMAN_VER}.tar.gz

  do_wget https://gitlab.com/libtiff/libtiff/-/archive/v${LIBTIFF_VER}/libtiff-v${LIBTIFF_VER}.tar.gz &&\
  tar -xf libtiff-v${LIBTIFF_VER}.tar.gz

  #Poppler
  do_wget https://poppler.freedesktop.org/poppler-${POPPLER_VER}.tar.xz &&\
  tar -xf poppler-${POPPLER_VER}.tar.xz
  
  #Cairo
  do_wget https://cairographics.org/releases/cairo-${CAIRO_VER}.tar.xz &&\
  tar -xf cairo-${CAIRO_VER}.tar.xz

  #Pango
  do_wget https://download.gnome.org/sources/pango/${PANGO_VER_MM}/pango-${PANGO_VER}.tar.xz &&\
  tar -xf pango-${PANGO_VER}.tar.xz

  #Shared-mime-info
  do_wget https://gitlab.freedesktop.org/xdg/shared-mime-info/-/archive/${SMI_VER}/shared-mime-info-${SMI_VER}.tar.gz &&\
  tar -xf shared-mime-info-${SMI_VER}.tar.gz

  #Librsvg
  do_wget https://gitlab.gnome.org/GNOME/librsvg/-/archive/${LIBRSVG_VER}/librsvg-${LIBRSVG_VER}.tar.gz &&\
  tar -xf librsvg-${LIBRSVG_VER}.tar.gz

  #GDK-Pixbuf
  do_wget https://download.gnome.org/sources/gdk-pixbuf/${GDK_PIXBUF_VER_MM}/gdk-pixbuf-${GDK_PIXBUF_VER}.tar.xz &&\
  tar -xf gdk-pixbuf-${GDK_PIXBUF_VER}.tar.xz

  #Atk
  do_wget https://download.gnome.org/sources/atk/${ATK_VER_MM}/atk-${ATK_VER}.tar.xz &&\
  tar -xf atk-${ATK_VER}.tar.xz

  #Wayland
  do_wget https://gitlab.freedesktop.org/wayland/wayland/-/archive/${WAYLAND_VER}/wayland-${WAYLAND_VER}.tar.gz &&\
  tar -xf wayland-${WAYLAND_VER}.tar.gz

  #Gtk
  do_wget https://download.gnome.org/sources/gtk/${GTK_VER_Major}.${GTK_VER_Minor}/gtk-${GTK_VER}.tar.xz &&\
  tar -xf gtk-${GTK_VER}.tar.xz 

  #PyGObject
  do_wget https://github.com/GNOME/pygobject/archive/refs/tags/${PYGOBJECT_VER}.tar.gz -O pygobject-${PYGOBJECT_VER}.tar.gz &&\
  tar -xf pygobject-${PYGOBJECT_VER}.tar.gz

  #RDKit
  do_wget https://github.com/rdkit/rdkit/archive/refs/tags/Release_${RDKIT_VER}.tar.gz &&\
  tar -xf Release_${RDKIT_VER}.tar.gz &&\
  mv rdkit-Release_${RDKIT_VER} RDKit_${RDKIT_VER}

  #MMDB
  do_wget https://www2.mrc-lmb.cam.ac.uk/personal/pemsley/coot/dependencies/mmdb2-${MMDB_VER}.tar.gz &&\
  tar -xf mmdb2-${MMDB_VER}.tar.gz

  #GSL
  do_wget https://ftp.gnu.org/gnu/gsl/gsl-${GSL_VER}.tar.gz &&\
  tar -xf gsl-${GSL_VER}.tar.gz

  #GEMMI
  do_wget https://github.com/project-gemmi/gemmi/archive/refs/tags/v${GEMMI_VER}.tar.gz -O gemmi-${GEMMI_VER}.tar.gz &&\
  tar -xf gemmi-${GEMMI_VER}.tar.gz

  #Libccp4
  do_wget https://www2.mrc-lmb.cam.ac.uk/personal/pemsley/coot/dependencies/libccp4-${LIBCCP4_VER}.tar.gz &&\
  tar -xf libccp4-${LIBCCP4_VER}.tar.gz

  #Libssm
  do_wget https://www2.mrc-lmb.cam.ac.uk/personal/pemsley/coot/dependencies/ssm-${LIBSSM_VER}.tar.gz -O libssm-${LIBSSM_VER}.tar.gz &&\
  tar -xf libssm-${LIBSSM_VER}.tar.gz && mv -v ssm-${LIBSSM_VER} libssm-${LIBSSM_VER}
  ## This is some patch from the AUR. I don't know what it fixes
  ## But I guess we need it
  do_wget https://aur.archlinux.org/cgit/aur.git/plain/ssm.pc.in?h=libssm -O ssm.pc.in &&\
  cd libssm-${LIBSSM_VER} &&\
  cp ../ssm.pc.in ./ssm.pc.in &&\
  cd ..

  #Libclipper
  do_wget https://www2.mrc-lmb.cam.ac.uk/personal/pemsley/coot/dependencies/clipper-${LIBCLIPPER_VER}.tar.gz -O libclipper-${LIBCLIPPER_VER}.tar.gz &&\
  tar -xf libclipper-${LIBCLIPPER_VER}.tar.gz

  do_wget http://www.fftw.org/fftw-${FFTW_VER}.tar.gz &&\
  tar -xf fftw-${FFTW_VER}.tar.gz 
}

build_glib() {
  setup_build_env
  mkdir -p $BUILD_DIR/glib
  cd $BUILD_DIR/glib &&\
  rm -rf *
  pushd $DEPS_DIR/glib-${GLIB_VER}
  meson setup --prefix=$PREFIX $BUILD_DIR/glib
  popd
  meson compile && meson install
  cd ..
}

build_gobject_introspection() {
  setup_build_env
  mkdir -p $BUILD_DIR/gobject_introspection
  cd $BUILD_DIR/gobject_introspection &&\
  rm -rf *
  pushd $DEPS_DIR/gobject-introspection-${GOBJECT_INTROSPECTION_VER}
  meson setup --prefix=$PREFIX $BUILD_DIR/gobject_introspection
  popd
  meson compile && meson install
  cd ..
}


build_guile() {
  setup_build_env
  mkdir -p $BUILD_DIR/guile
  cd $BUILD_DIR/guile &&\
  rm -rf *
  $DEPS_DIR/guile-${GUILE_VER}/configure --prefix=$PREFIX --enable-shared \
  --disable-static  \
  --disable-error-on-warning
  make -j `nproc --all` && make install
  cd ..
}


build_swig() {
  setup_build_env
  mkdir -p $BUILD_DIR/swig
  cd $BUILD_DIR/swig &&\
  rm -rf *
  $DEPS_DIR/swig-${SWIG_VER}/configure --prefix=$PREFIX 
  make -j `nproc --all` && make install
  cd ..
}

build_boost() {
  setup_build_env
  rm -rf $BUILD_DIR/boost
  cp -a $DEPS_DIR/boost_${BOOST_VER_} $BUILD_DIR/boost
  cd $BUILD_DIR/boost
  ./bootstrap.sh --with-toolset=gcc-${GCC_COMPILER_VERSION} --with-libraries=serialization,regex,chrono,date_time,filesystem,iostreams,program_options,thread,math,random,system,atomic,container,context,fiber,coroutine,json,python,random &&\
  echo "using gcc : ${GCC_COMPILER_VERSION} : /usr/bin/g++-${GCC_COMPILER_VERSION} ; " >> user-config.jam &&\
  sed -i "s/gcc-${GCC_COMPILER_VERSION}/gcc/g" project-config.jam &&\
  BOOST_BUILD_PATH=. ./b2 link=shared variant=release threading=multi runtime-link=shared install --prefix=${PREFIX}
  cd ..
}

build_libepoxy() {
  setup_build_env
  mkdir -p $BUILD_DIR/libepoxy
  cd $BUILD_DIR/libepoxy &&\
  rm -rf *
  pushd $DEPS_DIR/libepoxy-${LIBEPOXY_VER}
  meson setup --prefix=$PREFIX $BUILD_DIR/libepoxy
  popd
  meson compile && meson install
  cd ..
}

build_harfbuzz() {
  setup_build_env
  mkdir -p $BUILD_DIR/harfbuzz
  cd $BUILD_DIR/harfbuzz &&\
  rm -rf *
  pushd $DEPS_DIR/harfbuzz-${HARFBUZZ_VER}
  meson setup --prefix=$PREFIX -Dtests=disabled $BUILD_DIR/harfbuzz
  popd
  meson compile && meson install
  cd ..
}

build_graphene() {
  setup_build_env
  mkdir -p $BUILD_DIR/graphene
  cd $BUILD_DIR/graphene &&\
  rm -rf *
  pushd $DEPS_DIR/graphene-${GRAPHENE_VER}
  meson setup --prefix=$PREFIX $BUILD_DIR/graphene
  popd
  meson compile && meson install
  cd ..
}

build_freetype() {
  setup_build_env
  mkdir -p $BUILD_DIR/freetype
  cd $BUILD_DIR/freetype &&\
  rm -rf *
  # We have to first build Freetype with CMake.
  # The reason is that CMake installs .cmake files
  # which later enable CMake to find Freetype
  # for libraries which depend upon it and build with CMake.
  #
  # Without this step, CMake finds Freetype
  # but gives an error anyway because
  # FindFreetype.cmake script is fucked up.
  cmake $DEPS_DIR/freetype-${FREETYPE_VER} \
  -DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_BUILD_TYPE=release -D BUILD_SHARED_LIBS=true  &&\
  cmake --build . && cmake --install . &&\
  # Meson build is commented-out because it makes CMake builds crash
  # rm -rf *
  # pushd $DEPS_DIR/freetype-${FREETYPE_VER}
  # meson setup --prefix=$PREFIX $BUILD_DIR/freetype
  # popd
  # meson compile && meson install
  cd ..
}

build_fontconfig() {
  setup_build_env
  mkdir -p $BUILD_DIR/fontconfig
  cd $BUILD_DIR/fontconfig &&\
  rm -rf *
  pushd $DEPS_DIR/fontconfig-${FONTCONFIG_VER}
  meson setup --prefix=$PREFIX $BUILD_DIR/fontconfig
  popd
  meson compile && meson install
  cd ..
}

build_pixman() {
  setup_build_env
  mkdir -p $BUILD_DIR/pixman
  cd $BUILD_DIR/pixman &&\
  rm -rf *
  pushd $DEPS_DIR/pixman-${PIXMAN_VER}
  meson setup --prefix=$PREFIX $BUILD_DIR/pixman
  popd
  meson compile && meson install
  cd ..
}

build_poppler() {
  setup_build_env
  mkdir -p $BUILD_DIR/poppler
  cd $BUILD_DIR/poppler &&\
  rm -rf *
  cmake -S $DEPS_DIR/poppler-${POPPLER_VER} -DENABLE_NSS3=OFF \
  -DENABLE_GPGME=OFF -DBUILD_GTK_TESTS=OFF -DBUILD_QT5_TESTS=OFF \
  -DBUILD_QT6_TESTS=OFF -DENABLE_BOOST=ON -DENABLE_QT5=OFF -DENABLE_QT6=OFF \
  -DENABLE_LIBOPENJPEG=none -DENABLE_LCMS=OFF -DENABLE_LIBCURL=ON -DENABLE_DCTDECODER=libjpeg \
  -DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_BUILD_TYPE=release
  cmake --build . && cmake --install .
  cd ..
}

build_tiff() {
  setup_build_env
  rm -rf $BUILD_DIR/libtiff
  cp -av $DEPS_DIR/libtiff-v${LIBTIFF_VER}/ $BUILD_DIR/libtiff
  cd $BUILD_DIR/libtiff
  ./autogen.sh --prefix=$PREFIX
  ./configure --prefix=$PREFIX
  make -j `nproc --all` && make install
  cd ..
}

build_cairo() {
  setup_build_env
  mkdir -p $BUILD_DIR/cairo
  cd $BUILD_DIR/cairo &&\
  rm -rf *
  pushd $DEPS_DIR/cairo-${CAIRO_VER}
  meson setup --prefix=$PREFIX $BUILD_DIR/cairo
  popd
  meson compile && meson install
  cd ..
}

build_pango() {
  setup_build_env
  mkdir -p $BUILD_DIR/pango
  cd $BUILD_DIR/pango &&\
  rm -rf *
  pushd $DEPS_DIR/pango-${PANGO_VER}
  meson setup --prefix=$PREFIX $BUILD_DIR/pango
  popd
  meson compile && meson install
  cd ..
}

build_smi() {
  setup_build_env
  mkdir -p $BUILD_DIR/shared_mime_info
  cd $BUILD_DIR/shared_mime_info &&\
  rm -rf *
  pushd $DEPS_DIR/shared-mime-info-${SMI_VER}
  meson setup --prefix=$PREFIX $BUILD_DIR/shared_mime_info
  popd
  meson compile && meson install
  cd ..
}

build_librsvg() {
  setup_build_env
  mkdir -p $BUILD_DIR/librsvg
  cd $BUILD_DIR/librsvg &&\
  rm -rf *
  $DEPS_DIR/librsvg-${LIBRSVG_VER}/autogen.sh --prefix=$PREFIX
  #Not needed I think?
  $DEPS_DIR/librsvg-${LIBRSVG_VER}/configure --prefix=$PREFIX
  make -j `nproc --all` && make install
  cd ..
}

build_gdk_pixbuf() {
  setup_build_env
  mkdir -p $BUILD_DIR/gdk_pixbuf
  cd $BUILD_DIR/gdk_pixbuf &&\
  rm -rf *
  pushd $DEPS_DIR/gdk-pixbuf-${GDK_PIXBUF_VER}
  meson setup --prefix=$PREFIX $BUILD_DIR/gdk_pixbuf -Dtests=false -Dman=false -Dgtk_doc=false
  popd
  meson compile && meson install
  cd ..
}

build_atk() {
  setup_build_env
  mkdir -p $BUILD_DIR/atk
  cd $BUILD_DIR/atk &&\
  rm -rf *
  pushd $DEPS_DIR/atk-${ATK_VER}
  meson setup --prefix=$PREFIX $BUILD_DIR/atk
  popd
  meson compile && meson install
  cd ..
}

build_wayland() {
  setup_build_env
  mkdir -p $BUILD_DIR/wayland
  cd $BUILD_DIR/wayland &&\
  rm -rf *
  pushd $DEPS_DIR/wayland-${WAYLAND_VER}
  meson setup --prefix=$PREFIX $BUILD_DIR/wayland -Dtests=false -Ddocumentation=false
  popd
  meson compile && meson install
  cd ..
}

build_gtk() {
  setup_build_env
  mkdir -p $BUILD_DIR/gtk
  cd $BUILD_DIR/gtk &&\
  rm -rf *
  pushd $DEPS_DIR/gtk-${GTK_VER}
  meson setup --prefix=$PREFIX $BUILD_DIR/gtk -Dbroadway-backend=true -Dwin32-backend=false -Dmacos-backend=false \
      -Dmedia-gstreamer=disabled  -Dintrospection=enabled -Dvulkan=disabled -Dbuild-tests=false
  popd
  meson compile && meson install
  cd ..
}


build_pygobject() {
  setup_build_env
  mkdir -p $BUILD_DIR/pygobject
  cd $BUILD_DIR/pygobject &&\
  rm -rf *
  pushd $DEPS_DIR/pygobject-${PYGOBJECT_VER}
  meson setup --prefix=$PREFIX $BUILD_DIR/pygobject
  popd
  meson compile && meson install
  cd ..
}

 
build_rdkit() {
  setup_build_env
  mkdir -p $BUILD_DIR/rdkit
  cd $BUILD_DIR/rdkit &&\
  rm -rf *
  cmake -S $DEPS_DIR/RDKit_${RDKIT_VER} \
  -DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_BUILD_TYPE=release \
  -DRDK_BUILD_CAIRO_SUPPORT=ON \
  -DRDK_BUILD_INCHI_SUPPORT=OFF \
  -DRDK_INSTALL_COMIC_FONTS=OFF \
  -DRDK_INSTALL_INTREE=OFF 

  cmake --build . && cmake --install .
  cd ..
}

build_mmdb2() {
  setup_build_env
  mkdir -p $BUILD_DIR/mmdb2
  cd $BUILD_DIR/mmdb2 &&\
  rm -rf *
  $DEPS_DIR/mmdb2-${MMDB_VER}/configure --prefix=$PREFIX --enable-shared
  make -j `nproc --all` && make install
  cd ..
}


build_gsl() {
  setup_build_env
  mkdir -p $BUILD_DIR/gsl
  cd $BUILD_DIR/gsl &&\
  rm -rf *
  $DEPS_DIR/gsl-${GSL_VER}/configure --prefix=$PREFIX 
  make -j `nproc --all` && make install
  cd ..
}

build_gemmi() {
  setup_build_env
  mkdir -p $BUILD_DIR/gemmi
  cd $BUILD_DIR/gemmi &&\
  rm -rf *
  cmake -S $DEPS_DIR/gemmi-${GEMMI_VER} \
  -DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_BUILD_TYPE=release -DBUILD_SHARED_LIBS=true #\
  # -DUSE_PYTHON=1 requires pybind11
  cmake --build . && cmake --install .
  cd ..
}


build_libccp4() {
  setup_build_env
  additional_build_env_setup
  mkdir -p $BUILD_DIR/libccp4
  cd $BUILD_DIR/libccp4 &&\
  rm -rf *
  $DEPS_DIR/libccp4-${LIBCCP4_VER}/configure --prefix=$PREFIX \
  --enable-shared --disable-static \
  --datadir=$PREFIX/share/ccp4 
  make -j `nproc --all` && make install
  cd ..
}


build_libssm() {
  setup_build_env
  additional_build_env_setup
  rm -rf $BUILD_DIR/libssm
  cp -a $DEPS_DIR/libssm-${LIBSSM_VER} $BUILD_DIR/libssm
  cd $BUILD_DIR/libssm 
  aclocal
  libtoolize --automake --copy
  autoconf
  automake --copy --add-missing --gnu
  ./configure --prefix=$PREFIX \
  --enable-shared --disable-static \
  --enable-ccp4 
  # unrecognized option
  #--with-mmdb=$PREFIX \
  make -j `nproc --all` && make install
  cd ..
}



build_libclipper() {
  setup_build_env
  additional_build_env_setup
  mkdir -p $BUILD_DIR/libclipper
  cd $BUILD_DIR/libclipper &&\
  rm -rf *
  $DEPS_DIR/clipper-${LIBCLIPPER_VER_PRE}/configure --prefix=$PREFIX \
  --enable-shared --disable-static \
  --enable-contrib --enable-ccp4 \
  --enable-cif --enable-mmdb --enable-minimol \
  --enable-cns --enable-phs --enable-fortran
  make -j `nproc --all` && make install
  cd ..
}


  # --enable-mpi \
  #--enable-type-prefix \
  #--enable-float
FFTW_CONFIGURE="./configure F77=gfortran --prefix=$PREFIX   --enable-shared --disable-static  --enable-openmp --enable-threads --with-gcc --with-gcc-ld"


build_fftw() {  
  setup_build_env
  rm -rf $BUILD_DIR/fftw
  cp -av $DEPS_DIR/fftw-${FFTW_VER} $BUILD_DIR/fftw
  cd $BUILD_DIR/fftw
  ${FFTW_CONFIGURE}
  make -j `nproc --all` && make install
  cd ..
  
  rm -rf $BUILD_DIR/sfftw
  cp -av $DEPS_DIR/fftw-${FFTW_VER} $BUILD_DIR/sfftw
  cd $BUILD_DIR/sfftw
  ${FFTW_CONFIGURE} --enable-type-prefix --enable-float
  make -j `nproc --all` && make install
  cd ..
}

build_dependencies() {
  build_glib
  build_gobject_introspection
  build_guile
  build_swig
  build_libepoxy
  build_boost
  # We seem to need to rebuild that because of some weird gir madness
  build_gobject_introspection
  # and glib again
  build_glib
  # and gobject_introspection again, don't ask me why
  build_gobject_introspection
  build_graphene
  build_harfbuzz
  build_freetype
  build_fontconfig
  build_pixman
  build_cairo
  # Rebuild after building cairo
  build_gobject_introspection
  # Rebuild after building cairo
  build_harfbuzz
  # Also builds fribidi
  build_pango
  build_smi
  # Also builds libjeg
  build_gdk_pixbuf
  build_librsvg
  build_tiff
  build_poppler
  # Rebuild after librsvg
  build_cairo
  # After librsvg
  build_gdk_pixbuf
  build_atk
  build_wayland
  build_gtk
  build_pygobject
  build_fftw
  build_rdkit
  build_mmdb2
  build_gsl
  build_gemmi
  build_libccp4
  build_libssm
  build_libclipper
}

download_coot() {
  cd $COOT_DOWNLOAD_DIR
  git clone --depth 2 https://github.com/hgonomeg/coot.git
}

build_coot() {
  cd $COOT_BUILD_DIR
  setup_build_env
  additional_build_env_setup
  ./autogen.sh
    #--with-libdw --with-backward
  ./configure --prefix=$PREFIX \
    --disable-static --with-enhanced-ligand-tools \
    --with-rdkit-prefix=$PREFIX \
    --with-boost=$PREFIX  --with-gemmi=$PREFIX \
    --with-boost-thread=boost_thread \
    --with-boost-python="boost_python${PYTHON_VER_MAJOR}${PYTHON_VER_MINOR}"
    SHELL=/bin/bash \
    PYTHON=python3 \
    CXXFLAGS="${CXXFLAGS} -ggdb -O2 -march=native -Wreturn-type -Wl,--as-needed -Wno-sequence-point -Wsign-compare -Wno-unknown-pragmas" &&\
    sed -i "`grep -n \"BOOST_CPPFLAGS =\" $COOT_BUILD_DIR/pyrogen/Makefile | cut -f1 -d:`s/-pthread//" $COOT_BUILD_DIR/pyrogen/Makefile &&\
    make -j `nproc --all` && make install
}

setup_all_and_build_coot() {
  initial_setup
  download_dependencies
  build_dependencies
  download_coot
  build_coot
}

