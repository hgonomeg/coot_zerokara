# Adding Build Dependencies to Build Scripts

A skill for correctly adding new dependencies to build automation scripts, with verification against upstream sources.

## Overview

Adding a build dependency requires five coordinated components:
1. **Version declaration** - Specify the exact release version
2. **Dependency list** - Add to build order before dependents
3. **Build function** - Define how to compile the package
4. **Download recipe** - Fetch the source from upstream
5. **Arch version mirror** - Add the package to `check_arch_versions.sh` (repo root)
   so the version-audit helper keeps tracking it

Each must be verified against the upstream project before merging.

---

## Step 1: Identify and Verify the Dependency

### Check if it's truly needed
- Review the upstream project's documentation (README, meson_options.txt, CMakeLists.txt)
- Determine if it's **required** or **optional**
- For optional features, check if they can be disabled via build flags

**Example:**
```bash
# Check if libheif is optional in glycin:
curl https://raw.githubusercontent.com/GNOME/glycin/main/meson_options.txt
# Look for loader options and whether heif is a separate option
```

### Find the latest release
Use GitHub API to find the exact version:
```bash
curl -s https://api.github.com/repos/owner/project/releases/latest | \
  grep -o '"tag_name": "[^"]*"'
# Output: "tag_name": "v1.4.0"
# Strip 'v' prefix if present: 1.4.0
```

---

## Step 2: Verify Build System and Flags

### Default feature policy: enable everything, minus tests/examples/docs

Build each library with **as many features enabled as possible** — the bundled libs should
be at least as capable as the distro packages they replace. This is *especially* true when
a feature's sub-dependency is **already in our stack**: turn the feature **on**, don't
disable it (e.g. sqlite finds our readline → `--enable-readline`; a lib that can use our
zlib / openssl / icu / libxml2 → enable that backend). The only things to switch **off** are
**tests, examples, fuzzers, benchmarks, and documentation / man pages** — they cost build
time and pull tooling deps (docbook, sphinx, gtk-doc) without shipping anything users need.

So the default flag shape is "all features on, build-extras off":
- cmake: `-DXXX_ENABLE_TESTS=OFF -DXXX_ENABLE_EXAMPLES=OFF -DXXX_BUILD_DOCS=OFF` (leave feature toggles at their enabled defaults)
- meson: `-Dtests=false -Dexamples=false -Ddocs=false` (leave feature options enabled)
- configure: `--without-tests --without-examples --without-docbook` and keep the `--enable-<feature>` switches

Only disable a genuine feature when it needs a dependency we deliberately don't ship and
can't easily add — and call that out explicitly in your summary.

### Check what build system is used
```bash
# For cmake projects
curl https://raw.githubusercontent.com/owner/project/TAG/CMakeLists.txt

# For meson projects  
curl https://raw.githubusercontent.com/owner/project/TAG/meson.build

# Look for option() declarations with your feature name
```

### Verify cmake/meson options are correct
**Common mistakes:**
- Using `BUILD_TESTING` instead of project-specific `XXX_ENABLE_TESTS`
- Assuming options exist without checking the source
- Using different naming conventions (meson uses `-D`, cmake uses `-D`)

**Verification checklist:**
```
☐ Test/fuzzer disabling: Check exact option name in CMakeLists.txt
☐ Shared vs static: Verify default and whether -DBUILD_SHARED_LIBS is respected
☐ Examples/tools: Check if XXX_ENABLE_EXAMPLES, XXX_ENABLE_TOOLS exist
☐ Documentation: Verify ENABLE_DOCS, ENABLE_MANPAGES options if present
```

**Example:**
```bash
# WRONG - highway uses HWY_ENABLE_TESTS, not BUILD_TESTING
build_highway() {
  build_with_cmake highway ${HIGHWAY_VER} -DBUILD_TESTING=OFF
}

# CORRECT
build_highway() {
  build_with_cmake highway ${HIGHWAY_VER} \
    -DBUILD_SHARED_LIBS=ON \
    -DHWY_ENABLE_TESTS=OFF \
    -DHWY_ENABLE_EXAMPLES=OFF
}
```

### ALWAYS verify optimization level and debug symbols honor `$btype`
The generic helpers do this for you: `build_with_cmake` maps `$btype` to
`Release`/`RelWithDebInfo`, `build_with_meson` to `release`/`debugoptimized`, and
`build_with_configure` injects `-O2` (opt) / `-O2 -g` (debug) on the configure line. If
you use them, you're covered.

**A hand-rolled build is the danger.** Two traps, both verified to bite in this repo:
- **The `-O0` trap:** the script exports `CFLAGS=-I$PREFIX/include`, and a *set* `CFLAGS`
  suppresses the build system's own `-O2`/`-O3` default (autoconf, ncurses, openssl's
  `--release`, ICU's `--enable-release` — all emit **no `-O`** under our `CFLAGS`). So a
  hand-rolled configure/Make build silently compiles at `-O0` unless you inject `-O`.
- **No debug symbols:** debug builds must add `-g`; opt builds shouldn't carry it.

So for any hand-rolled build, mirror the helper explicitly:
```sh
[ "$btype" = "debug" ] && __opt="-O2 -g" || __opt="-O2"
CFLAGS="${CFLAGS} ${__opt}" CXXFLAGS="${CXXFLAGS} ${__opt}" ./configure ...
# openssl-style config: pass ${__opt} as a config arg; cmake/meson: use the buildtype var.
```
**Verify it actually took** (a set CFLAGS is silently honored, so don't assume) — in a
throwaway CI container, run the package's configure with `CFLAGS=-I/x` exported and grep
the generated Makefile for `-O`:
```bash
CFLAGS="-I/x" ./configure ... && grep -m1 -E '^ *CFLAGS' Makefile   # must show -O2
```

---

## Step 3: Verify the Download URL

### ALWAYS use the official release tarball, never an auto-generated snapshot

Fetch the project's **official release tarball** — the one upstream publishes and
signs/checksums on its release page (SourceForge `download.sourceforge.net/...`,
Savannah, `ftp.gnu.org`, the GitHub *Releases* **assets**, the project's own site).

**Never use a VCS auto-snapshot**: `github.com/<o>/<r>/archive/refs/tags/<tag>.tar.gz`,
`codeload.github.com/.../tar.gz/...`, GitLab `/-/archive/...`. These are regenerated
from the tag on the fly — they have no stable checksum, may omit bundled/pre-generated
files (autotools `configure`, vendored sources), and can change content under the same
tag. Use them **only** as a genuine last resort when upstream publishes no release
asset, and say so in your summary.

Check the Arch PKGBUILD `source=` array (below) — it points at the canonical upstream
tarball and is the quickest way to find the official URL.

```bash
# Example: libpng's official source is the SourceForge release tarball, NOT the GitHub
# tag snapshot:
#   GOOD: https://download.sourceforge.net/libpng/libpng-1.6.58.tar.xz
#   BAD:  https://github.com/pnggroup/libpng/archive/refs/tags/v1.6.58.tar.gz
```

### Use Arch PKGBUILD as a reference for uncertainty

When uncertain about download URLs or how optional dependencies are handled, check the Arch Linux PKGBUILD:

```bash
# Format:
https://gitlab.archlinux.org/archlinux/packaging/packages/{package}/-/raw/main/PKGBUILD

# Example:
https://gitlab.archlinux.org/archlinux/packaging/packages/libjxl/-/raw/main/PKGBUILD?ref_type=heads

# Look at:
# - sources array: shows download URLs (may need to deduce the actual format)
# - depends/makedepends: what's required vs optional
# - build() function: what options are used (Arch builds comprehensively)
```

**Note:** The URL format shown in `sources=` is often variable-based. Deduce the actual URL from the pattern. Arch typically enables all optional features, but you don't have to—make feature choices explicit to the user.

### Handle unexpected sub-dependencies

When a dependency reveals sub-dependencies (e.g., libjxl requires highway):

**Ask the user explicitly:**
> "Package X depends on Y. Should I:
> 1. Add Y to the build dependency chain (before X)
> 2. Build X without feature Y (disable via build flag)"

**Example from this interaction:**
```
libjxl failed without highway.
User decision: Add highway as explicit dependency.
Result: highway → libjxl → bubblewrap → glycin
```

Let the user choose. Some sub-dependencies can be disabled via build flags (like libheif in glycin), while others are required (like highway in libjxl).

### Find the correct (official) archive URL format

Prefer, in order: the project's own download host, then a release asset uploaded to the
forge. These are the published tarballs, not snapshots.

```bash
# Project download sites / mirrors (official release tarballs):
https://download.sourceforge.net/{project}/{project}-{VERSION}.tar.xz
https://download.savannah.gnu.org/releases/{project}/{project}-{VERSION}.tar.xz
https://ftp.gnu.org/gnu/{project}/{project}-{VERSION}.tar.gz
https://www.cairographics.org/releases/{project}-{VERSION}.tar.xz

# GitHub *Releases* — the uploaded ASSET (a real release tarball), under /releases/download/:
https://github.com/owner/repo/releases/download/v{VERSION}/{project}-{VERSION}.tar.xz
# (Check the release page for the exact asset name; it often differs from the repo name.)
```

If — and only if — upstream publishes no release asset, fall back to the tag snapshot
(`.../archive/refs/tags/...`) and note the fallback in your summary.

### Test the URL before committing
Follow redirects and confirm you land on a real tarball, not an HTML error page:
```bash
curl -sIL "$URL" | grep -iE '^HTTP|^content-type|^content-length'
# Want a final 'HTTP .. 200', content-type application/octet-stream (or x-xz/gzip),
# and a content-length in the hundreds-of-KB+ range. text/html = wrong URL.
```

**Common issues:**
- Auto-snapshot instead of the official release tarball (see the rule above)
- Pre-built binaries instead of source (check release assets)
- Missing 'v' prefix in tag name
- Deprecated mirror URLs
- API URLs that require redirects

---

## Step 3.5: Verify the dependency chain with pacman

Before deciding *where* in `BUILD_DEPENDENCIES` the package goes, find — empirically,
not by guessing — **which other packages in the build depend on it** and **which
packages it depends on**. The list is order-sensitive: a dependency must be built before
every consumer. On an Arch box, `pacman -Si` is the source of truth for these edges.

This protects against two failure modes:
1. The new lib is placed *after* something that needs it → that consumer builds without
   it (often silently, with a feature auto-disabled).
2. The new lib needs an input that isn't ready yet → it fails to build. **Inputs can live
   in the toolchain phase** (zlib, openssl, ncurses, readline, libffi, Python, cmake are
   built there, before `BUILD_DEPENDENCIES`), so "not in the deps list" does **not** mean
   "not available". Check the toolchain phase too.

### Find consumers of the new lib (who must come after it)
Map every `BUILD_DEPENDENCIES` entry to its Arch package name (they often differ:
`glib`→`glib2`, `freetype`→`freetype2`, `tiff`→`libtiff`, `gdk_pixbuf`→`gdk-pixbuf2`,
`gtk`→`gtk4`; chem/niche libs may have no repo pkg — note those as unverifiable). Then
scan each one's **full** `Depends On` field for your lib:

```bash
# NB: the Bash tool's shell is zsh, which does NOT word-split unquoted $vars in a for
# loop — run this under bash, and parse the MULTI-LINE 'Depends On' field (pacman wraps
# it across lines; matching only the first line silently misses dependencies).
bash <<'EOF'
NEWLIB=libpng                       # arch package name of the lib you're adding
# dep-name:arch-pkg pairs, in BUILD_DEPENDENCIES order:
maps="util_linux:util-linux glib:glib2 harfbuzz:harfbuzz freetype:freetype2 cairo:cairo \
      poppler:poppler libjxl:libjxl gtk:gtk4 ..."   # include EVERY entry, even 'no repo pkg' ones
for m in $maps; do
  dep=${m%%:*}; arch=${m##*:}
  info=$(pacman -Si "$arch" 2>/dev/null)
  [ -z "$info" ] && { printf "%-20s %-16s [no repo pkg]\n" "$dep" "$arch"; continue; }
  if printf '%s' "$info" | sed -n '/^Depends On/,/^Optional Deps/p' | grep -qiE "$NEWLIB"; then
    printf "%-20s %-16s REQUIRES %s\n" "$dep" "$arch" "$NEWLIB"
  fi
done
EOF
```

Every package printed `REQUIRES` must sit **after** the new lib in `BUILD_DEPENDENCIES`.
Watch for packages that appear **twice** (e.g. `harfbuzz`, `gdk_pixbuf`): the *first*
pass may legitimately predate your lib if that pass doesn't use it (features are
auto-detected and the earlier pass runs before the consumer is built) — reason about the
specific pass, don't just look at the name.

### Sanity-check the reverse edge (inputs that must come before it)
Confirm the new lib's own hard deps are already built earlier — in `BUILD_DEPENDENCIES`
*or* the toolchain phase:

```bash
pacman -Si "$NEWLIB" | sed -n '/^Depends On/,/^Optional Deps/p'
# e.g. libpng -> zlib: zlib is built in the toolchain phase, so libpng anywhere in the
# deps list is fine.
```

---

## Step 4: Add to Build Script

### Part A: Declare the version
**Location:** After other version declarations (near line 600+)

```bash
LIBJXL_VER=0.11.2
```

**Naming convention:** `{PACKAGE}_VER` in UPPERCASE, with underscores for hyphens.

### Part B: Add to BUILD_DEPENDENCIES
**Location:** In the `BUILD_DEPENDENCIES` list (around line 488)

```bash
BUILD_DEPENDENCIES="
  ...
  highway          # Add new dependencies...
  libjxl           # ...before their dependents
  bubblewrap
  glycin           # glycin depends on all three above
  ...
"
```

**Critical:** Maintain correct dependency order - dependencies must come before packages that use them.

### Part C: Create build function
**Location:** Near other build functions (around line 1100+)

```bash
build_libjxl () {
  build_with_cmake libjxl ${LIBJXL_VER} \
    -DBUILD_SHARED_LIBS=ON \
    -DBUILD_TESTING=OFF \
    -DJPEGXL_ENABLE_FUZZERS=OFF \
    -DJPEGXL_ENABLE_TOOLS=OFF \
    -DJPEGXL_ENABLE_EXAMPLES=OFF
}
```

**Follow existing patterns:**
- Use `build_with_cmake` for cmake projects
- Use `build_with_meson` for meson projects  
- Use `build_with_configure` for autotools projects
- Pass variables not hardcoded values

### Part D: Add download recipe
**Location:** In the download section (around line 1680+)

```bash
  # LibJXL
  do_wget https://github.com/libjxl/libjxl/archive/refs/tags/v${LIBJXL_VER}.tar.gz libjxl-${LIBJXL_VER}.tar.gz
```

**Pattern:** Comment header, then `do_wget` with URL and output filename.

### Part E: Mirror the version in the Arch audit helper
**File:** `check_arch_versions.sh` at the **repository root** (not the build script).

This helper compares the build script's pinned `*_VER` values against what Arch Linux
currently ships. It keeps its own hand-maintained list in an inline `PKGLIST` heredoc,
so a new dependency is invisible to it until you add a line. Append one line to that
heredoc in the form:

```
arch-package-name:SCRIPT_VAR:pinned-version
```

```bash
# Example, matching LIBJXL_VER=0.11.2 in the build script:
libjxl:LIBJXL_VER:0.11.2
```

**Rules:**
- The **first** field is the *pacman* package name (e.g. `gtk4`, `gdk-pixbuf2`,
  `python-gobject`) — it often differs from the build-script package name. Confirm it
  with `pacman -Ss` / the Arch package site if unsure.
- The **second** field is the exact `*_VER` variable name you declared in Part A.
- The **third** field is the literal pinned version (same value as the `*_VER`).
- If the package genuinely has no Arch counterpart, skip it — but note that in your
  summary so the omission is intentional, not forgotten.

**Keep it in sync on every change, not just additions:** when you *bump* a version,
update the third field here too; when you *remove* a dependency, delete its line.

---

## Step 5: Verify System Package Dependencies

If the new dependency requires system-level development packages (headers, libraries), add them to the package manager invocations.

**Locations to update:**
- openSUSE (zypper): `libpackage-devel`
- RHEL/Fedora (dnf/yum): `libpackage-devel`
- Debian/Ubuntu (apt): `libpackage-dev`
- Arch (pacman): `libpackage`

**Example:**
```bash
# openSUSE
$sudo zypper install -y \
  libseccomp-devel \  # Add here
  ... other packages ...

# Debian/Ubuntu
$sudo apt-get install \
  libseccomp-dev \    # Note: -dev not -devel
  ... other packages ...
```

---

## Verification Checklist

Before committing:

- [ ] **Upstream project verified** - Checked meson_options.txt / CMakeLists.txt
- [ ] **Version is current** - Used GitHub API to confirm latest release
- [ ] **Build options verified** - Checked actual source for exact option names
- [ ] **Features maximized** - All upstream features enabled (especially ones satisfied by
      libs already in our stack); only tests/examples/fuzzers/docs turned off
- [ ] **Optimization + debug symbols honor `$btype`** - Generic helpers handle it; for any
      hand-rolled build, inject `-O2`(opt)/`-O2 -g`(debug) and verify `-O` actually lands in
      the generated Makefile (the exported `CFLAGS` suppresses build-system `-O` defaults)
- [ ] **Official source, not a snapshot** - Release tarball (download host / release asset),
      not a `archive/refs/tags` or `/-/archive` VCS snapshot (fallback noted if unavoidable)
- [ ] **Download URL tested** - `curl -sIL <URL>` lands on a real tarball (HTTP 200,
      octet-stream/x-xz, sizeable content-length), not text/html
- [ ] **Dependency chain verified with pacman** (Step 3.5) - consumers found via
      `pacman -Si` all sit *after* the new lib; its own inputs (incl. toolchain-phase ones)
      sit before it
- [ ] **Dependency order correct** - Dependencies listed before dependents
- [ ] **All five components added:**
  - [ ] Version declaration (VER variable)
  - [ ] BUILD_DEPENDENCIES entry
  - [ ] Build function
  - [ ] do_wget call
  - [ ] `check_arch_versions.sh` PKGLIST line (or noted as having no Arch package)
- [ ] **Follows script conventions:**
  - [ ] Naming matches existing packages
  - [ ] Indentation consistent
- [ ] **System packages added** - If needed for distros that don't bundle headers

---

## Common Patterns

### Minimal cmake library (for use as dependency)
```bash
build_libjxl () {
  build_with_cmake libjxl ${LIBJXL_VER} \
    -DBUILD_SHARED_LIBS=ON \
    -DBUILD_TESTING=OFF \
    -DJPEGXL_ENABLE_TOOLS=OFF \
    -DJPEGXL_ENABLE_EXAMPLES=OFF
}
```

### Minimal meson library
```bash
build_glycin () {
  build_with_meson glycin ${GLYCIN_VER} \
    -Dtests=false \
    -Dloaders=glycin-image-rs,glycin-jxl,glycin-svg
}
```

### Simple configure/automake
```bash
build_libunistring () {
  build_with_configure libunistring ${LIBUNISTRING_VER}
}
```

---

## Troubleshooting

### "Dependency not found at build time"
- Verify it's in BUILD_DEPENDENCIES **before** the dependent package
- Check cmake/meson can actually find it (PKG_CONFIG_PATH, CMAKE_PREFIX_PATH set correctly)
- Run build system with verbose output to see actual errors

### "Build fails with missing headers"
- The dependency likely needs system-level development packages
- Add to package manager sections for your distro
- Test on that specific distro if possible

### "Download fails"
- Verify URL with `curl -I` before committing
- Check if it's a GitHub archive (202 redirect is expected)
- Try alternative mirrors if primary source fails

### "Build works locally but not in CI"
- Different distro versions have different package names
- System packages might be missing
- Verify package names across all distro sections

### "Package fails with missing sub-dependency"
When a dependency reveals it needs another package:

**Option 1: Add to build chain**
- Identify the missing package (check error message, look at PKGBUILD)
- Follow the full 5-step process to add it
- Place it in BUILD_DEPENDENCIES before the package that needs it

**Option 2: Disable the feature**
- Check if the feature is optional in upstream meson_options.txt / CMakeLists.txt
- Add build flag to disable it: `-Dfeature=disabled` or `-DFEATURE_ENABLE=OFF`
- Document why you disabled it

**Example:**
```bash
# Glycin without libheif (choose Option 2):
# Check meson_options.txt → loaders option → disable heif loader
-Dloaders=glycin-image-rs,glycin-jxl,glycin-svg

# libjxl without highway (choose Option 1):
# Option 2 not available (highway is required)
# Added highway to BUILD_DEPENDENCIES before libjxl
```

**Always ask the user** when this decision needs to be made.

---

## Real Example: Adding libjxl

```bash
# 1. Verify latest version
curl -s https://api.github.com/repos/libjxl/libjxl/releases/latest | \
  grep tag_name
# Result: v0.11.2

# 2. Check CMakeLists.txt for options
curl https://raw.githubusercontent.com/libjxl/libjxl/0.11.2/CMakeLists.txt | \
  grep -A2 "option(JPEGXL"
# Find: JPEGXL_ENABLE_TOOLS, JPEGXL_ENABLE_EXAMPLES, JPEGXL_ENABLE_FUZZERS

# 3. Test download URL
curl -s -I https://github.com/libjxl/libjxl/archive/refs/tags/v0.11.2.tar.gz | head -1
# Returns: HTTP/2 302 ✓

# 4. Add to script
# - LIBJXL_VER=0.11.2 in versions section
# - libjxl in BUILD_DEPENDENCIES (before glycin)
# - build_libjxl() function with correct flags
# - do_wget call with verified URL
```

---

## References

- GitHub API: https://docs.github.com/en/rest/releases/releases
- CMake options documentation pattern: `grep "^option(" CMakeLists.txt`
- Meson options pattern: Check `meson_options.txt`
- Build script conventions: Study existing similar packages in script
