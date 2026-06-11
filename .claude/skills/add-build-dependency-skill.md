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

### Find the correct archive URL format

**GitHub releases pattern:**
```bash
# Source archives (works even if releases page doesn't list them)
https://github.com/owner/repo/archive/refs/tags/v{VERSION}.tar.gz
https://github.com/owner/repo/archive/refs/tags/{VERSION}.tar.gz

# Verify with curl (302 redirect is normal):
curl -s -I https://github.com/google/highway/archive/refs/tags/1.4.0.tar.gz | head -1
# Should return: HTTP/2 302 (redirect to actual archive)
```

**Other sources:**
```bash
# GitLab releases
https://gitlab.com/owner/project/-/archive/{VERSION}/project-{VERSION}.tar.gz

# GNU project mirrors
https://ftp.gnu.org/gnu/{project}/{project}-{VERSION}.tar.gz

# Savannah projects
https://download.savannah.gnu.org/releases/{project}/{project}-{VERSION}.tar.gz
```

### Test the URL before committing
```bash
# Quick test - should return 2xx or 3xx status
curl -s -I "https://github.com/owner/repo/archive/refs/tags/v${VERSION}.tar.gz" | head -1
```

**Common issues:**
- Pre-built binaries instead of source (check release assets)
- Missing 'v' prefix in tag name
- Deprecated mirror URLs
- API URLs that require redirects

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
- [ ] **Download URL tested** - `curl -I <URL>` returns 2xx or 3xx status
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
  - [ ] Comments added
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
