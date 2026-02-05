# Multi-Platform Container Testing Proposal

## Motivation

The `create_venv.sh` and `install-uv.sh` scripts support multiple platforms. Our uv symlink fix (PR #37160, issue #37007) uses POSIX constructs designed for all of them, but was only verified on Ubuntu 22.04. To increase confidence, we should test on other supported platforms.

## Supported Platforms (from install-uv.sh)

| Platform | Docker Base Image | uv Install Method | uv Install Path | Priority |
|----------|-------------------|-------------------|-----------------|----------|
| Ubuntu 22.04 | `ubuntu:22.04` | pip --user | `~/.local/bin/uv` | **Already tested** |
| Ubuntu 24.04 | `ubuntu:24.04` | pip --user (PEP 668) | `~/.local/bin/uv` | High |
| Fedora 40+ | `fedora:40` | dnf system package | `/usr/bin/uv` | **Highest** |
| Debian 12 | `debian:12` | pip --user (PEP 668) | `~/.local/bin/uv` | Medium |
| RHEL/Rocky/Alma | `rockylinux:9` | dnf/yum | `/usr/bin/uv` or `~/.local/bin/uv` | Low |
| macOS | N/A | pip or standalone | `~/.local/bin/uv` | Cannot test in Docker |

## Why Fedora is Most Interesting

Fedora is the only platform where `install-uv.sh` uses `dnf install -y uv` to install uv as a **system package** to `/usr/bin/uv`. This means:
- `command -v uv` returns `/usr/bin/uv` (not `~/.local/bin/uv`)
- The symlink target is different: `python_env/bin/uv -> /usr/bin/uv`
- The symlink is technically redundant (since `/usr/bin` is always on PATH) but must not break anything
- Tests the "harmless redundancy" claim from the PR

## Why Ubuntu 24.04 Matters

Ubuntu 24.04 has several differences from 22.04:
- PEP 668 enforced: `pip install --user` may behave differently
- Python 3.12 is the default (create_venv.sh has special handling: sets `VENV_PYTHON_VERSION="3.12"`)
- Different system package versions (gcc, cmake, etc.)
- `install-uv.sh` uses `--break-system-packages` flag when needed

## Proposed Dockerfile Changes

### Option A: Parameterized Single Dockerfile (Recommended)

Add a `BASE_IMAGE` build arg:

```dockerfile
ARG BASE_IMAGE=ubuntu:22.04
FROM ${BASE_IMAGE}

# ... then branch on OS for package installation:
RUN . /etc/os-release && \
    case "$ID" in \
        ubuntu|debian) \
            apt-get update && apt-get install -y \
                sudo wget curl git git-lfs build-essential ... \
            ;; \
        fedora|rhel|centos|rocky|almalinux) \
            dnf install -y \
                sudo wget curl git git-lfs gcc gcc-c++ make ... \
            ;; \
    esac
```

### Option B: Separate Dockerfiles per Platform

```
Dockerfile.ubuntu2204   (current, rename)
Dockerfile.ubuntu2404
Dockerfile.fedora
Dockerfile.debian12
```

**Option A is better** - less duplication, easier to maintain.

### build_tt_docker.sh Changes

Add `--platform` flag:

```bash
# Usage:
./build_tt_docker.sh --platform ubuntu2204   # default
./build_tt_docker.sh --platform ubuntu2404
./build_tt_docker.sh --platform fedora40
./build_tt_docker.sh --platform debian12
```

Map platform to base image:
```bash
case "$PLATFORM" in
    ubuntu2204) BASE_IMAGE="ubuntu:22.04" ;;
    ubuntu2404) BASE_IMAGE="ubuntu:24.04" ;;
    fedora40)   BASE_IMAGE="fedora:40" ;;
    debian12)   BASE_IMAGE="debian:12" ;;
esac
```

Pass to Docker build:
```bash
docker build --build-arg BASE_IMAGE=$BASE_IMAGE ...
```

## Package Mapping (apt vs dnf)

Key packages that need mapping between Ubuntu/Debian (apt) and Fedora/RHEL (dnf):

| Ubuntu/Debian (apt) | Fedora/RHEL (dnf) |
|---------------------|-------------------|
| build-essential | gcc gcc-c++ make |
| python3-dev | python3-devel |
| python3-pip | python3-pip |
| python3-venv | python3-venv (or built-in) |
| libstdc++-12-dev | libstdc++-devel |
| libmpfr-dev | mpfr-devel |
| libgmp-dev | gmp-devel |
| libmpc-dev | libmpc-devel |
| libnuma-dev | numactl-devel |
| libhwloc-dev | hwloc-devel |
| libtbb-dev | tbb-devel |
| libcapstone-dev | capstone-devel |
| libopenmpi-dev | openmpi-devel |
| openmpi-bin | openmpi |
| git-lfs | git-lfs |
| cargo | cargo |
| pandoc | pandoc |
| graphviz | graphviz |
| doxygen | doxygen |
| kmod | kmod |
| pciutils | pciutils |
| clang / llvm | clang / llvm |

**Note:** Some packages may not exist on all platforms. The Dockerfile should handle missing packages gracefully.

## Verification Steps (same for all platforms)

After `create_venv.sh` runs, the verification step remains identical:

```dockerfile
RUN . $TT_METAL_HOME/python_env/bin/activate && \
    echo "=== Verifying uv availability after venv activation ===" && \
    echo "PATH=$PATH" && \
    which uv && \
    uv --version && \
    ls -la $TT_METAL_HOME/python_env/bin/uv && \
    echo "=== uv verification PASSED ===" && \
    deactivate
```

The `ls -la` shows the symlink target, which should differ per platform:
- Ubuntu/Debian: `python_env/bin/uv -> /root/.local/bin/uv`
- Fedora: `python_env/bin/uv -> /usr/bin/uv`

## Implementation Order

1. **Fedora 40** - highest value (different uv install path)
2. **Ubuntu 24.04** - second highest (PEP 668, Python 3.12)
3. **Debian 12** - nice to have (similar to Ubuntu 24.04)
4. **Rocky Linux 9** - lowest priority (similar to Fedora)

## Known Blockers

- **#36993** (GCC constexpr lambda in `reflect` library) will cause the tt-train build to fail on platforms using GCC. This is independent of the uv fix and affects all platforms equally.
- **CMake version:** The Dockerfile installs CMake 3.30.9 from source, which works on all Linux platforms.
- **install_dependencies.sh:** Currently only supports Ubuntu/Debian. Fedora/RHEL would need either a separate deps script or skipping this step with manual package installation in the Dockerfile.

## Related Issues and PRs

- **#37007:** uv not found after venv activation (the fix we're verifying)
- **PR #37160:** The uv symlink fix
- **#36993:** GCC build failure (next blocker after uv fix)
- **Container verification branch:** `verify/issue-37007-uv-path-fix` in ivoitovych/tt-container
