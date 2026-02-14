# Minimal Bootstrap Build Experiment

**Date:** 2026-02-14
**Branch:** `test-install-dependencies-self-sufficient`
**tt-metal commit:** `c765173f20` (main)
**Patches applied:** uv symlink fix (#37007), compiler selection fix (#36993)

## Objective

Test whether `install_dependencies.sh` is self-sufficient — i.e., whether the
Dockerfile can pre-install only a minimal set of bootstrap packages and let
`install_dependencies.sh` handle everything else (cmake, clang, build tools,
libraries).

## Result: SUCCESS

The full build completed successfully with only 10 bootstrap packages
pre-installed. All build phases passed:

| Phase | Duration | Status |
|-------|----------|--------|
| Bootstrap packages (apt) | 6.2s | OK |
| git clone (3 repos) | 76.5s | OK |
| Checkout + submodules + LFS | 13.8s | OK |
| Merge 2 patches | 3.1s | OK |
| `install_dependencies.sh` | 55.8s | OK (1 harmless warning) |
| `create_venv.sh` | 34.3s | OK |
| `build_metal.sh --debug --build-all` | 615.9s | OK |
| `uv pip install -e tt-train` | 130.8s | OK |
| tt-train C++ build (cmake + ninja) | 164.2s | OK |
| tt-smi install | 11.3s | OK |
| Image export | 321.3s | OK |
| **Total** | **~22 min** | **OK** |

Final image: `ivoitovych-tt-metal-env-built-debug-c765173f20:latest`

## Bootstrap Packages (Pre-installed in Dockerfile)

These 10 packages are the only ones installed before `install_dependencies.sh` runs:

| Package | Why pre-installed | Could install_dependencies.sh handle it? |
|---------|-------------------|------------------------------------------|
| `sudo` | install_dependencies.sh requires root via sudo | **No** — script checks `EUID != 0` and tells user to use sudo. In Docker (running as root), sudo is needed because the script calls `sudo apt-get`. Cannot be removed without modifying install_dependencies.sh. |
| `wget` | Used by install_dependencies.sh to download LLVM, SFPI, MPI | **Redundant** — install_dependencies.sh also installs wget, but needs it available *before* the package install step (used during system prep to fetch GPG keys). Keep for safety. |
| `curl` | Used by install_dependencies.sh for Kitware GPG key download | **Redundant** — same situation as wget. Needed during repo setup before main package install. Keep for safety. |
| `ca-certificates` | Required for HTTPS downloads (git clone, wget, curl) | **Redundant** — install_dependencies.sh installs it during system prep. But without it, the initial `git clone` over SSH/HTTPS would fail. **Must keep.** |
| `git` | Clone tt-metal repo before install_dependencies.sh runs | **Redundant** — install_dependencies.sh installs git. But we need it *before* the script exists (to clone the repo). **Must keep.** |
| `git-lfs` | Pull LFS objects from tt-metal repo | Pre-build dependency — must be available before install_dependencies.sh runs. **Must keep.** |
| `openssh-client` | SSH-based git clone from GitHub | **Optional** — tt-metal is open source, HTTPS clone works without it. Needed only for SSH-based clone workflow. |
| `ccache` | Compiler cache for faster rebuilds | **Optional** — build acceleration only. Counterproductive for smallest images and clean builds. |
| `kmod` | `modprobe` for kernel module management at runtime | **Runtime only** — not needed for build. Useful for device interaction in development containers. |
| `pciutils` | `lspci` for hardware detection at runtime | **Runtime only** — not needed for build. Useful for hardware diagnostics in development containers. |

## Analysis of Bootstrap Packages

### Truly required (cannot be removed): 6 packages

These must be pre-installed because they're needed *before* install_dependencies.sh
can run, or because install_dependencies.sh doesn't install them:

| Package | Reason |
|---------|--------|
| `sudo` | install_dependencies.sh calls `sudo apt-get` internally |
| `ca-certificates` | HTTPS connectivity for git clone (runs before install_dependencies.sh) |
| `git` | Clone the repo (runs before install_dependencies.sh) |
| `git-lfs` | LFS pull (not in install_dependencies.sh) |
| `openssh-client` | SSH-based git clone (not in install_dependencies.sh) |
| `wget` | Used by install_dependencies.sh during repo setup, before package install |

### Optional (could be removed for minimal images): 4 packages

| Package | Category | Notes |
|---------|----------|-------|
| `curl` | Redundant | install_dependencies.sh installs curl, but also uses it during system prep (Kitware GPG key fetch). If the prep step ordering changes, removal could break. Low priority — ~200 KB. |
| `openssh-client` | Workflow | Only needed for SSH-based git clone. tt-metal is open source — HTTPS clone works without it. |
| `ccache` | Build acceleration | Not needed for correctness. Counterproductive for smallest images and clean reproducible builds. |
| `kmod` | Runtime | Only needed for `modprobe tenstorrent` at container runtime. Not a build dependency. |
| `pciutils` | Runtime | Only needed for `lspci` at container runtime. Not a build dependency. |

## Packages Not in install_dependencies.sh (By Design)

These packages are not in `install_dependencies.sh` and **should not be added**
— they are outside its scope:

| Package | Category | Rationale |
|---------|----------|-----------|
| `git-lfs` | Pre-build dependency | Must be installed *before* `install_dependencies.sh` runs — the repo clone and LFS pull happen first. Not a build dependency, it's a source checkout dependency. |
| `openssh-client` / `openssh-clients` | Optional | tt-metal is open source. HTTPS clone works without SSH. Only needed if cloning via SSH (private forks, faster auth). |
| `ccache` | Optional | Build acceleration only. Counterproductive for smallest images and clean reproducible builds. A container/CI concern, not a build dependency. |
| `kmod` | Runtime only | Kernel module tools (`modprobe`, `lsmod`). Not needed for building — only for loading the tenstorrent driver at runtime. |
| `pciutils` | Runtime only | PCI utilities (`lspci`). Not needed for building — only for hardware detection and diagnostics at runtime. |

**Conclusion:** `install_dependencies.sh` correctly focuses on *build* dependencies.
The packages above belong in the Dockerfile or host system setup, not in the
build dependency installer.

## Warning in install_dependencies.sh

One harmless warning was observed:

```
./install_dependencies.sh: line 407: [: 2204.5 LTS (Jammy Jellyfish): integer expression expected
```

This is a version comparison bug where the full OS description string (including
"LTS (Jammy Jellyfish)") is compared as an integer. It doesn't affect functionality —
the script proceeds to download and install `openmpi-ulfm` normally.

## What install_dependencies.sh Installed

The script installed 140+ packages including:

**System prep (93 packages):** python3, gpg, gnupg, jq, lsb-release,
software-properties-common, systemd, and their dependencies.

**Build tools and libraries (140+ packages):** build-essential, cmake 4.2.3
(from Kitware repo), g++-12, ninja-build, pkg-config, pandoc, libssl-dev,
python3-dev, python3-pip, python3-venv, libhwloc-dev, libnuma-dev, libtbb-dev,
libcapstone-dev, libc++-20-dev, libc++abi-20-dev, openmpi-bin, libopenmpi-dev,
and dependencies.

**LLVM/Clang (via llvm.sh):** clang-20, lldb-20, lld-20, clangd-20.

**SFPI:** sfpi 7.25.0 (downloaded .deb from GitHub releases, hash-verified).

**MPI ULFM:** openmpi-ulfm 5.0.7-1 (downloaded .deb from GitHub releases).

## Conclusion

`install_dependencies.sh` is fully self-sufficient for building tt-metal on
Ubuntu 22.04. It correctly handles all build dependencies: cmake (from Kitware
repo), clang-20 (via llvm.sh), build-essential, g++-12, ninja, and all required
libraries.

The Dockerfile bootstrap splits cleanly into three categories:

1. **Pre-build essentials** (cannot remove): `sudo`, `git`, `git-lfs`,
   `ca-certificates`, `wget` — needed before install_dependencies.sh runs.
2. **Optional for workflow**: `openssh-client` (SSH clone), `curl` (redundant
   with wget but used by install_dependencies.sh during repo setup), `ccache`
   (build acceleration).
3. **Runtime only**: `kmod`, `pciutils` — not needed for build, only for
   device interaction.

The current 10-package bootstrap is already minimal and well-justified.
`install_dependencies.sh` does not need changes — the missing packages are
outside its scope by design.
