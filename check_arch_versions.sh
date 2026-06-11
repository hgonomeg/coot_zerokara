#!/bin/bash
# check_arch_versions.sh — Compare pinned versions from the build script
# against what's currently installed via pacman on Arch Linux.
#
# Each line is:  pacman-package-name:SCRIPT_VAR:pinned-version
# Blank lines and #-comments are ignored.

set -euo pipefail

while IFS=: read -r pkg scriptvar scriptver; do
  [[ -z "$pkg" || "$pkg" == \#* ]] && continue

  archver=$(pacman -Qi "$pkg" 2>/dev/null | awk '/^Version/ {print $3}' | head -1) || true

  if [[ -z "$archver" ]]; then
    printf "%-30s  %-35s  %-14s  %s\n" "$pkg" "$scriptvar" "$scriptver" "NOT INSTALLED"
    continue
  fi

  # Strip epoch prefix and -pkgrel suffix for comparison
  arch_base="${archver%%-*}"           # drop -pkgrel
  arch_base="${arch_base#*:}"          # drop epoch (e.g. 1:4.22.4 → 4.22.4)

  script_base="${scriptver%%-*}"
  script_base="${script_base#*:}"

  # Normalise underscores to dots (rdkit: 2026_03_3 vs 2026.03.3)
  arch_base="${arch_base//_/.}"
  script_base="${script_base//_/.}"

  if [[ "$arch_base" == "$script_base" ]]; then
    printf "%-30s  %-35s  %-14s  %-14s  MATCH\n" "$pkg" "$scriptvar" "$scriptver" "$archver"
  else
    printf "%-30s  %-35s  %-14s  %-14s  NEWER\n" "$pkg" "$scriptvar" "$scriptver" "$archver"
  fi
done <<'PKGLIST'
glib2:GLIB_VER:2.88.1
gobject-introspection:GOBJECT_INTROSPECTION_VER:1.86.0
guile:GUILE_VER:3.0.11
swig:SWIG_VER:4.4.1
harfbuzz:HARFBUZZ_VER:14.2.1
freetype2:FREETYPE_VER:2.14.3
fontconfig:FONTCONFIG_VER:2.18.1
pixman:PIXMAN_VER:0.46.4
libtiff:LIBTIFF_VER:4.7.1
poppler:POPPLER_VER:26.05.0
curl:CURL_VER:8.20.0
cairo:CAIRO_VER:1.18.4
pango:PANGO_VER:1.57.1
librsvg:LIBRSVG_VER:2.62.3
highway:HIGHWAY_VER:1.4.0
lcms2:LCMS2_VER:2.19.1
libjxl:LIBJXL_VER:0.11.2
libcap:LIBCAP_VER:2.78
bubblewrap:BUBBLEWRAP_VER:0.11.2
glycin:GLYCIN_VER:2.1.1
gdk-pixbuf2:GDK_PIXBUF_VER:2.44.6
at-spi2-core:AT_SPI2_CORE_VER:2.60.4
gtk4:GTK_VER:4.22.4
adwaita-icon-theme:ADWAITA_ICON_THEME_VER:50.0
openblas:OPENBLAS_VER:0.3.33
fftw2:FFTW_VER:2.1.5
gsl:GSL_VER:2.8
eigen:EIGEN_VER:5.0.1
libogg:LIBOGG_VER:1.3.6
libvorbis:LIBVORBIS_VER:1.3.7
wayland:WAYLAND_VER:1.25.0
wayland-protocols:WAYLANDPROTOCOLS_VER:1.49
elfutils:ELFUTILS_VER:0.195
libjpeg-turbo:LIBJPEG_VER:3.1.4.1
libunistring:LIBUNISTRING_VER:1.2
gc:GC_VER:8.2.12
glm:GLM_VER:1.0.3
pcre2:PCRE2_VER:10.47
boost:BOOST_VER:1.91.0
libepoxy:LIBEPOXY_VER:1.5.10
graphene:GRAPHENE_VER:1.10.8
shared-mime-info:SMI_VER:2.4
libffi:LIBFFI_VER:3.5.2
python-gobject:PYGOBJECT_VER:3.56.3
rdkit:RDKIT_VER:2026_03_3
libdwarf:LIBDWARF_VER:2.3.1
backward-cpp:LIBBACKWARD_VER:1.6
icu:ICU_VER:78.3
libxml2:LIBXML2_VER:2.15.3
bzip2:BZIP2_VER:1.0.8
util-linux:UTIL_LINUX_VER:2.42.1
ncurses:NCURSES_VER:6.6
readline:READLINE_VER:8.3
openssl:OPENSSL_VER:3.6.3
PKGLIST
