# dl_and_build_coot.sh — Coot from-source build script

## What this is

A single, self-contained POSIX **`/bin/sh`** script — `dl_and_build_coot.sh`
(at the repository root; this is the one and only active build driver) —
that downloads, compiles, and packages [Coot](https://github.com/pemsley/coot)
**1.x** together with its entire dependency stack, from source, into a single
relocatable prefix. It is maintained by Global Phasing Ltd (GPhL); the generated
README points users at `buster-develop@globalphasing.com`.

The script builds Coot **1.x only**. Do not reintroduce 0.9-era (Python 2 / GTK2)
dependencies — gtkglext, libgnomecanvas, goocanvas, libart, pygtk, pillow, freeglut,
etc. — unless explicitly asked.

> **Standing goal — a truly relocatable tarball (read [`RELOCATABILITY.md`](RELOCATABILITY.md)).**
> The long-term direction is to build **essentially the entire dependency stack from
> source** and bundle it, so the tarball runs on end-user machines that have only a
> minimal host base (graphics environment + C/C++ runtime/glibc). We must not require
> users to have dependency libraries installed, and must not link against many system
> libraries (e.g. **ICU, OpenSSL, libmount** must be built ourselves). Concretely: prefer
> moving libraries *out* of the per-distro OS-package `case` and *into* the from-source
> `$BUILD_DEPENDENCIES` stack. Keep this in mind for any dependency-related change.

## Repository layout

This file (`CLAUDE.md`) and the build script both live at the repository root.

- `dl_and_build_coot.sh` — **the active script**, and the subject of essentially all
  of this document. All section/line references below are to this file.

## Helper scripts (repo root)

Two standalone helpers sit alongside this file. They are developer/CI tooling, not
part of the build itself.

- `check_arch_versions.sh` — a **`bash`** script that audits the build script's pinned
  dependency versions against what Arch Linux currently ships. It carries an inline
  `PKGLIST` heredoc of `pacman-package:SCRIPT_VAR:pinned-version` lines, queries each
  with `pacman -Qi`, normalises both sides (strips pacman's epoch prefix and `-pkgrel`
  suffix), and prints `MATCH` / `NEWER` / `NOT INSTALLED` per package. Use it to spot
  dependencies that have fallen behind upstream. **Its `PKGLIST` is a hand-maintained
  mirror of the `*_VER` block in the build script** — it must be kept in sync whenever
  a dependency is added, removed, or version-bumped (see the add-dependency skill).
  Run it on an Arch box: `./check_arch_versions.sh`.

- `fetch_ci_logs.py` — a **Python 3** script (stdlib only; needs the `gh` CLI
  authenticated, or a `GITHUB_TOKEN`) that pulls GitHub Actions build logs for offline
  /AI triage. For each run it downloads the `build-logs-<distro>` artifacts (the
  collected `my_*.log` files, unwrapping the nested ZIP→`.tar.zst`) plus each matrix
  job's failing terminal output (`terminal_output.log`), into `./ci_logs/run_<id>_<conclusion>/<distro>/`
  with a `SUMMARY.txt`. Defaults to recent **failed** runs; `-r <id>` / `-l` (latest) /
  `-d <distro>` / `-n <max>` narrow it. The repo is hard-coded as `hgonomeg/coot_zerokara`
  (override with `--repo`). The matrix-job name parsing assumes CI names jobs
  `build (<distro>, …)`. Read `terminal_output.log` first, then drill into the
  individual `my_*.log` files.

## Continuous integration

Two pipelines build the script across distros:
- `.github/workflows/build-coot.yml` — GitHub Actions matrix (`ubuntu:24.04/26.04`,
  `debian:trixie`, `fedora:43/44`, `archlinux:latest`, `rockylinux:9`,
  `opensuse/leap:15.6`). On failure it tars the `my_*.log` files — the glob now also
  catches root-level logs like `my_git_clone.log` — into a `build-logs-<distro>` artifact.
  On success it uploads the packaged Coot tarball (`coot-build/coot-*.tar.zst`) as a
  `coot-<distro>-x86_64` artifact — so users can grab a ready-built Coot from a green run
  without building it themselves (the README points them here).
- `Jenkinsfile` — a single `buildready-rocky` image; archives the same logs.

Both run the build as the script's **four phases, one step/stage each**
(`-download-only` → `-toolchain-only` → `-deps-only` → `-coot-stage-only`), so a failure
points at the exact phase. The first step installs OS packages
(`-use-os-package-manager`); the rest pass `-no-use-os-package-manager` since they share
the same container. The GitHub workflow adds a step between deps and Coot that
drops the source/build trees under `coot-build/{deps,build}` (keeping the `my_*.log`
files at their original paths so the failure-log step still collects them) — once the
dependencies are installed in the prefix those trees are dead weight, and dropping them
keeps the runner from running out of disk during the Coot build/packaging. **These pipelines are a correctness
check of the script and are
deliberately NOT cached** — every run is a full from-scratch build (a script-hash cache
key would invalidate on nearly every commit anyway). The phase split exists so that
**Coot's own CI** (a separate repo) can cache the prebuilt dependency stack; that caching
is not configured here.

**CI failures are usually transient** (crates.io network / runner out-of-disk), not
script bugs — triage with `fetch_ci_logs.py` before assuming otherwise.

## How to run it

Meant to be run **interactively, from inside the directory where you want everything
to land** — all downloads, builds and the install prefix are created in `$PWD`
(`PREFIX=$(pwd)`). Key flags (see `usage()` near the top):

- `-nthreads N` — parallelism (default: all cores)
- `-tag <tag>` / `-branch <branch>` — which Coot to build (default tag `main`)
- `-use-os-package-manager` / `-no-use-os-package-manager` — install (or skip) the
  distro's system packages first; **installing is the default now** (needs root/sudo;
  per-distro package lists live in the big `case` near the top)
- `-no_chapi` — skip the headless "Chapi" Python API build
- `-fulltar` — build a "full" tarball; **also fetches the full refmac monomer library**
  (default is a minimal tarball — the bundled ~115-monomer set ships either way)
- `-debug` / `-clean` / `-distributable` / `-noninteractive`
- `-patch <file>` — apply a patch to the Coot tree before building
- **Build-phase selectors** (mutually exclusive; none given = run the whole build):
  `-download-only`, `-toolchain-only`, `-deps-only`, `-coot-stage-only` — run just one
  of the four phases and stop (see "Top-level control flow"). For caching CI: run
  `-download-only` → `-toolchain-only` → `-deps-only` in the same dir to populate and
  cache the prefix, then `-coot-stage-only` after restoring it. Passing two selectors is
  an error.

Supported distros: AlmaLinux, Arch, Debian, Fedora, openSUSE, Rocky, Ubuntu
(detected from `/etc/os-release` etc.).

## Top-level control flow

Everything is functions until the very bottom of the file, which is the actual driver.
The driver is a **four-phase dispatch** keyed on `$stage` (set by the `-*-only` flags;
default `all`). The OS-package install block near the top runs unconditionally *before*
the dispatch, so wget/dev-libs are present in every phase. `setup_build_env` also runs
first, unconditionally (every phase needs its env vars + `$PREFIX/bin` on PATH).

```
setup_build_env            # always: PKG_CONFIG_*, LD_*, CC/CXX/FC, PYTHONPATH …

# phase 1 — download   (stage = all | download)
download_all
  ├─ download_toolchain    # do_wget Python, CMake, Ninja, rustup-init.sh (NO build)
  └─ download_dependencies # do_wget every dependency tarball into $DEPS_DIR
                           #   — NB: neither downloads Coot itself

# phase 2 — toolchain  (stage = all | toolchain)
initial_setup             # calls download_toolchain first (idempotent), then BUILDS:
                          #   fresh Python, pip meson/etc, newer CMake + Ninja,
                          #   install Rust + cargo-c

# phase 3 — deps       (stage = all | deps)
build_dependencies        # iterate $BUILD_DEPENDENCIES, call build_<name>

# phase 4 — coot       (stage = all | coot)
download_coot             # git clone the requested tag/branch
build_coot                # autogen → configure (writes+runs my_configure.sh) → make → install
build_chapi               # (unless -no_chapi) cmake build of the headless API
complete_coot             # fetch reference-structures (+ full monomer library if -fulltar)
extract_fonts             # unpack bundled Inter/JetBrains/DejaVu/Noto fonts
package_coot_prep         # move stray Coot ELF into libexec; bin/ → coot-wrapper.sh symlinks
create_coot_wrapper       # emit bin/coot-wrapper.sh   (see "runtime launcher" below)
create_coot_env           # emit bin/coot-env.sh       (sourceable full env)
package_coot_minimal | package_coot   # tar up the result
```

A `-*-only` flag runs exactly one phase and stops; with none, all four run in order
(identical to the old linear behaviour, except **all downloads now happen up front** in
phase 1 instead of being interleaved with the toolchain build). The phases are designed
so Coot's own CI can build + cache the dependency stack (phases 1–3, no Coot) and then
build Coot alone against the restored cache (`-coot-stage-only`). The old single
`setup_all_and_build_coot` wrapper is gone — the driver owns orchestration.

## Key concepts an editor must understand

### Directory layout (all under `$PREFIX = $(pwd)`)
- `$DEPS_DIR` (`$PREFIX/deps`) — unpacked source trees
- `$BUILD_DIR` (`$PREFIX/build`) — out-of-tree build dirs, one per package
- `$PREFIX/{bin,lib,lib64,libexec,share,include,…}` — the install tree
- `$CARGO_HOME` / `$RUSTUP_HOME` — Rust kept inside `$PREFIX` (not `$HOME`)
- `$COOT_BUILD_DIR` (`$PREFIX/$COOT_DIR`) — the cloned Coot source tree

### The dependency list and dispatcher
- `$BUILD_DEPENDENCIES` is a whitespace-separated, **order-sensitive** list set
  unconditionally near the top (fixed; not user-overridable). Order matters and **some packages appear
  more than once on purpose** (e.g. `glib`, `harfbuzz`, `gdk_pixbuf`,
  `glycin`) — the stack has circular-ish bootstrap needs.
- `build_dependencies()` loops the list and `eval`s `build_<name>`. The **N-th**
  occurrence of a package calls `build_<name>`, `build_<name>2`, `build_<name>3`, …
  (the integer suffix comes from `${build_count#1}`). So `build_glib`/`build_glib2`,
  `build_harfbuzz`/`build_harfbuzz2`, `build_glycin`/`build_glycin2`,
  `build_gdk_pixbuf`/`build_gdk_pixbuf2` are the 1st/2nd-pass variants — usually the
  2nd pass enables a feature that needed a dependency built in between (e.g. glycin's
  GTK4 bindings, gdk-pixbuf's glycin support). **If you add a package name twice to the
  list, you must define the numbered variant function.**
- Hyphens in a dep name are stripped to form the shell-var/function name
  (`at-spi2-core` → vars use `atspi2core`, but the function is `build_at_spi2_core`;
  match the existing naming when adding one).

### Per-package idempotency / "done" markers
Each `build_*` is guarded by a `.my_done${MY_DONE_EXT}` sentinel file in its build
dir, so re-running the script **skips already-built packages**. `MY_DONE_EXT` is set
to the pass number on repeat builds (so 2nd-pass markers are `.my_done2`). Coot itself
uses a finer set of stamps: `.my_autogen_done`, `.my_configure_done`,
`.my_make_done1`, `.my_make_done`. To force a rebuild of one package, delete its
stamp(s).

### The generic builders
Most `build_<pkg>` functions are thin wrappers over one of three helpers, which all
follow the same log-to-`my_*.log` + sentinel pattern:
- `build_with_meson <pkg> <ver> [meson args…]`
- `build_with_configure [-autogen] <pkg> <ver> [configure args…]`
  (`build_with_autogen_and_configure` = the `-autogen` form)
- `build_with_cmake <pkg> <ver> [cmake args…]`

They expect the unpacked source at `$DEPS_DIR/<pkg>-<ver>` and build into
`$BUILD_DIR/<pkg>`. Packages whose tarball top-dir doesn't match `<pkg>-<ver>` get
renamed/symlinked in `download_dependencies` (e.g. coordgenlibs→coordgen,
rdkit-Release_*→rdkit-*, ssm→libssm). A few packages (boost, libtiff, libssm,
libclipper, fftw) are special-cased with their own hand-written build bodies instead
of the generic helpers.

### Version pinning
Every dependency version is a `*_VER` variable in one block near the top
(`CMAKE_VER`, `PYTHON_VER_*`, `BOOST_VER`, `GTK_VER*`, `RDKIT_VER`, …). To bump a
dependency, edit its `*_VER` there; the download URL and build function both reference
it. Python version is split into `PYTHON_VER_MAJOR`/`MINOR`/`PATCH` (a leftover from
the py2/py3 era — now constant 3.14.x but still referenced in several places:
`PYTHONPATH`, the `-lpython3.14` link flag, and the `boost_python314` lib name).

### Downloading: `do_wget`
`do_wget <url> [output-name [max-retries]]` is the **only** download primitive. It is
a 3-tier fetch: (1) GPhL contrib mirror at `$url_contrib` by full path, (2) contrib
mirror by basename, (3) upstream URL with retries/back-off. It also auto-unpacks
tarballs and logs to `my_get_<pkg>.log`. New dependencies should be fetched through it.

### Compiler selection
A loop near the top picks the newest available GCC in `[GCC_VER_MIN, GCC_VER_CEILING]`
and sets `CC`/`CXX`/`FC` plus `GCC_COMPILER_VERSION` and `GCC_COMMAND_EXT`
(e.g. `-13`). `GCC_COMMAND_EXT` is threaded into boost's toolset and fftw's `F77`.

### The runtime launcher (env + wrapper + symlinks)
Three pieces, each emitted via a **single-quoted heredoc** / created at packaging time;
all ship in the tarball and are relocatable (they derive the prefix from their own
location).

- **`bin/coot-env.sh`** (`create_coot_env`) — the **single source of truth** for the
  runtime environment. Sourceable by end users (`. bin/coot-env.sh`) and sourced by the
  wrapper. Exports `LD_LIBRARY_PATH`, `PYTHONHOME`, all `COOT_*` data dirs, Guile, XDG,
  bundled fontconfig, `GI_TYPELIB_PATH`. Deliberately does **not** set `LANG/LC_*` (so
  sourcing it doesn't clobber a user's locale). This is also the chapi entry point:
  `. bin/coot-env.sh; python3 -c 'import coot_headless_api'`.
- **`bin/coot-wrapper.sh`** (`create_coot_wrapper`) — self-locates, sources
  `coot-env.sh`, sets launch-only `LANG=C`, then **resolves the target by lookup**:
  `libexec/$invoked_name` → `libexec/$invoked_name-bin` → the one alias `coot`→`coot-1`,
  and execs it. Validation is **warnings-only** (never hard-fails). Keeps `--ldd`,
  `--strace`, `--debug`, `-v`. (The old `eval` name-map, the Darwin/DYLD branch, and the
  `--ccp4` stub were all removed.)
- **`package_coot_prep`** — makes every Coot launcher in `bin/` a plain symlink to
  `coot-wrapper.sh` (name = libexec binary minus a trailing `-bin`); also moves any
  Coot-named ELF binary that landed in `bin/` (e.g. `coot-bfactan`, `coot-mmrrcc`) into
  `libexec/` first. "Coot tool" = name matching `coot*`/`layla*`/`mini-rsr*` (so GTK
  internals `gio*`/`at-spi*` are left alone). No shims, no `.orig` backups.

Note: `bin/python3` and the other dependency tools (`cmake`, `gtk4-*`, `fc-*`, …) are
**not** wrapped — they only work after `coot-env.sh` is sourced (their `$PREFIX` libs
aren't on the default loader path). The `error()`/`warning()`/`usage()` inside the
wrapper heredoc belong to the wrapper, not the main script.

## Conventions to follow when editing

- **POSIX sh only** — no bashisms. Note the idioms already in use: `[ "X$VAR" != "X" ]`
  for non-empty tests, backtick command substitution, `expr` for arithmetic,
  `printf`/`cat <<EOF` for output.
- Every build step writes its output to a `my_<step>.log${MY_DONE_EXT}` and on failure
  calls `error "see \`mypwd\`/my_<step>.log"`. Keep that pattern — `error` prints the
  OS release and exits 1; `mypwd` prints the path relative to `$PREFIX`.
- Comments in this script are unusually thorough and explain *why* (workarounds for
  upstream bugs, packaging quirks, GCC false-positives, etc.). Preserve that density;
  when you add a workaround, say what it's working around.
- A `/tmp/<scriptbasename>.debug` trace is appended to by `do_wget` and the generic
  builders — leave those `echo … >> /tmp/…debug` lines intact.
