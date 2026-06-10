# Coot from-source build script

`dl_and_build_coot.sh` is a single, self-contained POSIX `/bin/sh` script that downloads, compiles, and packages [Coot](https://github.com/pemsley/coot) 1.x — the macromolecular model-building program — together with its entire dependency stack, from source, into one relocatable prefix. The result is a self-contained tarball that runs without touching the system's libraries. It is maintained by Global Phasing Ltd.

If you just want a working build of Coot rather than to build it yourself, head to this repository's CI (GitHub Actions) and download the latest artifacts.

## Usage

Run it interactively from inside the (empty) directory where you want everything to land — all sources, build trees, and the install prefix are created in `$PWD`:

```sh
./dl_and_build_coot.sh
```

By default it installs the required OS packages via the system package manager, then builds the bootstrap toolchain (a fresh Python, CMake, Ninja, Rust), every dependency, and finally Coot and its headless "Chapi" Python API. Because it installs packages through the system package manager, **running the script requires administrative privileges** (root/sudo). The final tarball, by contrast, is expected to run without any administrative privileges for end users.

Useful flags (`-h` lists them all):

- `-nthreads <N>` — parallelism (default: all cores)
- `-tag <tag>` / `-branch <branch>` — which Coot to build (default tag `main`)
- `-no-use-os-package-manager` — skip installing distro packages
- `-fulltar` — build a full tarball (static libs, docs, full refmac monomer library)
- `-no_chapi` — skip the headless Python API
- `-debug` / `-distributable` / `-noninteractive` / `-patch <file>`
- `-download-only` / `-toolchain-only` / `-deps-only` / `-coot-stage-only` — run a single build phase and stop (lets CI build and cache the dependency stack, then build Coot alone against it)

Tested on AlmaLinux, Arch (June 2026), Debian 13, Fedora 43/44, openSUSE Leap 15.6, Rocky 9, and Ubuntu 24.04/26.04. When the build finishes, source `bin/coot-env.sh` from the prefix and launch via `bin/coot`.
