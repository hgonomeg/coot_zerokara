# Project goal: a *truly* relocatable Coot tarball

> **Status: standing long-term goal / direction.** This is not a single task or PR —
> it is an ongoing initiative that should steer many future changes to
> `dl_and_build_coot.sh`. Any human or language model working on this repository must be
> aware of it. It is important.

## The goal

The tarball produced by `dl_and_build_coot.sh` must be **truly relocatable**: it should
run on an end user's machine **without requiring them to install any dependency
libraries**, and **without linking against system libraries we are not permitted or able
to rely on**. In practice this means building **essentially the entire dependency stack
from source** into the install prefix, and shipping it.

We are moving *away* from "install these dev packages from the distro and link against
them" and *towards* "build it ourselves and bundle it."

## Why this matters

1. **Users won't have the libraries.** We cannot expect end users to have the necessary
   dependency libraries installed on their systems. The tarball has to be self-contained.
2. **We are not allowed to link against many system libraries.** For a number of system
   libraries, linking against the host's copy is not acceptable (policy/licensing/ABI
   stability). Those must be our own from-source builds, shipped in the prefix.
3. **Relocatable = self-contained.** The only things we rely on from the host should be a
   minimal, near-universal base (below). Everything else travels in the tarball.

## What the host machine may provide (the bare minimum)

The acceptable set of things we assume the host already has is small, roughly:

- a **graphics environment** (GPU drivers / the system GL stack and the windowing-system
  client pieces that must match the host);
- the **C / C++ runtime** (glibc, `libstdc++`, `libgcc`);
- possibly a **few other core system libraries** (to be decided case by case).

Anything outside this base should be built from source and bundled.

## What must move from "system package" to "built from source"

Today the big per-distro OS-package `case` near the top of `dl_and_build_coot.sh`
installs a large set of `-devel`/`-dev` libraries from the distro, and many of those end
up linked into the shipped Coot binaries and libraries. The initiative is to
**progressively move such libraries out of the system-install lists and into the
from-source `$BUILD_DEPENDENCIES` stack.**

Examples explicitly called out as *must build ourselves* (non-exhaustive):

- **ICU**
- **OpenSSL / SSL**
- **libmount** (util-linux)
- … and many more — the full list comes from auditing what the shipped artifacts link
  against (see below).

## How to make progress (practical guidance)

This is incremental. A typical step:

1. **Audit linkage.** Run `ldd` over the shipped binaries/libraries (the wrapper's
   `--ldd` flag helps) to find which system libraries they pull in. Anything outside the
   allowed base (above) is a candidate to build ourselves.
2. **Bring the candidate in-tree** by following the authoritative procedure in
   **`.claude/skills/add-build-dependency-skill.md`** — its five coordinated components
   (`*_VER`, `$BUILD_DEPENDENCIES` entry in correct order, `build_<name>`, `do_wget`,
   and the `check_arch_versions.sh` PKGLIST mirror), the upstream URL/option
   verification, and its **"always ask the user"** rule when a library reveals a
   sub-dependency (add it to the chain vs disable the feature). Don't re-derive the
   procedure from this doc — that skill is the source of truth.
3. **Drop the replaced library from the system lists.** Once it builds from source,
   remove the corresponding `-devel`/`-dev` entries from the per-distro OS-package `case`
   so we stop linking the host copy. (Note: a newly-added library may still need *other*
   system build deps — skill Step 5 covers adding those; the goal is to keep shrinking
   the set over time, not to strand a build.)
4. **Verify clean.** Confirm on the CI matrix images (clean containers, *without* the dev
   packages) that the tarball still builds and the result runs — that is the real test of
   relocatability.

## Non-goals / cautions

- Do **not** try to also build the bare-minimum host base (graphics drivers, glibc, the
  C/C++ runtime) — that is what we deliberately rely on.
- This remains **Coot 1.x only** — see `CLAUDE.md`; do not reintroduce 0.9-era deps.
- Expect this to span many commits. Each library moved from system to source is a valid,
  self-contained increment toward the goal.
