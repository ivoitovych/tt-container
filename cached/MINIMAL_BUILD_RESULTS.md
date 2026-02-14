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
| `git-lfs` | Pull LFS objects from tt-metal repo | **Not installed** by install_dependencies.sh. **Must keep.** |
| `openssh-client` | SSH-based git clone from GitHub | **Not installed** by install_dependencies.sh. **Must keep.** |
| `ccache` | Compiler cache for faster rebuilds | **Not installed** by install_dependencies.sh. **Must keep** (or add to install_dependencies.sh). |
| `kmod` | `modprobe` for kernel module management at runtime | **Not installed** by install_dependencies.sh. **Must keep** for runtime device access. |
| `pciutils` | `lspci` for hardware detection at runtime | **Not installed** by install_dependencies.sh. **Must keep** for runtime diagnostics. |

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

### Could potentially be removed: 1 package

| Package | Notes |
|---------|-------|
| `curl` | install_dependencies.sh installs curl, but also uses it during system prep (Kitware GPG key). If the prep step is rearranged to install curl first, this could be removed. Low priority — 200 KB. |

### Runtime-only (not needed for build, needed for device interaction): 2 packages

| Package | Notes |
|---------|-------|
| `kmod` | Only needed at container runtime for `modprobe tenstorrent`. Could be installed after the build, but is tiny (~100 KB) and useful during development. |
| `pciutils` | Only needed at runtime for `lspci`. Same consideration as kmod. |

### Build acceleration (optional): 1 package

| Package | Notes |
|---------|-------|
| `ccache` | Not needed for correctness — only for build speed. Could be removed if ccache is not desired. In practice, always wanted. |

## Packages install_dependencies.sh Should Install But Doesn't

These packages are commonly needed for tt-metal development and container usage
but are missing from `install_dependencies.sh`:

| Package | Purpose | Impact if missing |
|---------|---------|-------------------|
| `git-lfs` | Git Large File Storage — tt-metal uses LFS for binary assets | LFS pull fails; missing model weights, test data |
| `openssh-client` / `openssh-clients` | SSH client for GitHub access | Cannot clone private repos via SSH |
| `ccache` | Compiler cache | No build acceleration; every build is from scratch |
| `kmod` | Kernel module tools (`modprobe`, `lsmod`) | Cannot load/manage tenstorrent kernel driver |
| `pciutils` | PCI utilities (`lspci`) | Cannot detect/diagnose Tenstorrent hardware |

**Recommendation:** These 5 packages should be added to `install_dependencies.sh`
to make it truly self-sufficient for both development and deployment. They are
small, universally available across apt/dnf/yum, and have no license concerns.

### Package names across distributions

| Purpose | apt (Debian/Ubuntu) | dnf (Fedora/Rocky/Alma/CentOS) |
|---------|---------------------|-------------------------------|
| Git LFS | `git-lfs` | `git-lfs` |
| SSH client | `openssh-client` | `openssh-clients` |
| Compiler cache | `ccache` | `ccache` |
| Kernel modules | `kmod` | `kmod` |
| PCI utilities | `pciutils` | `pciutils` |

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
Ubuntu 22.04. The Dockerfile only needs to pre-install packages that are required
*before* the script runs (git, sudo, ca-certificates, wget) or that the script
doesn't cover (git-lfs, openssh-client, ccache, kmod, pciutils).

The current 10-package bootstrap is already minimal. At most, `curl` could be
removed (saving ~200 KB), but it's not worth the risk of breakage if
install_dependencies.sh's internal ordering changes.

Adding 5 packages (git-lfs, openssh-client/clients, ccache, kmod, pciutils) to
`install_dependencies.sh` would make it truly self-contained for container and
bare-metal development environments alike.
