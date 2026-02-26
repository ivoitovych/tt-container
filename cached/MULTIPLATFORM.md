# Multi-Platform OS Support

The container build system supports multiple Linux distributions as base images.
This document describes the supported platforms, their status, and known limitations.

## Supported Platforms

### Main (tested, expected to work)

| Preset | Base Image | Package Manager | Notes |
|--------|-----------|----------------|-------|
| `ubuntu2204` | `ubuntu:22.04` | apt | Default. Primary CI/CD platform for tt-metal. |
| `ubuntu2404` | `ubuntu:24.04` | apt | Supported upstream since late 2024. |
| `fedora40` | `fedora:40` | dnf | Community-supported. |

### Experimental (builds may require fixes)

| Preset | Base Image | Package Manager | Notes |
|--------|-----------|----------------|-------|
| `debian12` | `debian:12` | apt | Should work (Debian-family). Not tested upstream. |
| `rocky9` | `rockylinux:9` | dnf | RHEL 9 binary-compatible. See [Known Limitations](#known-limitations). |
| `alma9` | `almalinux:9` | dnf | RHEL 9 binary-compatible. See [Known Limitations](#known-limitations). |
| `centos9` | `quay.io/centos/centos:stream9` | dnf | RHEL 9 upstream. See [Known Limitations](#known-limitations). |

### Excluded

| Distribution | Reason |
|-------------|--------|
| RHEL 9 | Requires paid Red Hat subscription for package repositories. |

## Usage

```bash
# Build with default (Ubuntu 22.04)
./build_tt_docker.sh

# Build with a specific OS preset
./build_tt_docker.sh --os ubuntu2404
./build_tt_docker.sh --os fedora40
./build_tt_docker.sh --os rocky9

# Build with a custom base image
./build_tt_docker.sh --base-image myregistry/myimage:mytag
```

The OS label is included in the image name:
```
<user>-tt-metal-env-<os>-built-<type>-<hash>:latest

# Examples:
ivoitovych-tt-metal-env-ubuntu2204-built-debug-c765173f20:latest
ivoitovych-tt-metal-env-fedora40-built-debug-c765173f20:latest
ivoitovych-tt-metal-env-rocky9-built-debug-c765173f20:latest
```

## Known Limitations

The following limitations apply to Red Hat-family distributions (Rocky, Alma, CentOS Stream):

1. **`install_dependencies.sh` Red Hat support is incomplete.**
   The `prep_redhat_system()` function is a stub — it prints a message but installs nothing.
   LLVM/Clang installation is skipped on non-Debian systems. This means builds on
   Red Hat-family distros will likely fail at the dependency installation step until
   upstream adds full support.

2. **MPI ULFM and hugepages setup skipped on non-Debian.**
   These are handled only in the Debian/Ubuntu code path of `install_dependencies.sh`.

3. **Package name differences.**
   Some packages have different names between apt and dnf (e.g., `openssh-client`
   vs `openssh-clients`). The Dockerfile bootstrap layer handles this, but
   `install_dependencies.sh` may have hardcoded Debian package names.

## Licensing

All base images are **free and open source** with no paid license or subscription required.

| Distribution | License | Docker Image Source | Trademark Restrictions |
|-------------|---------|--------------------|-----------------------|
| Ubuntu 22.04 / 24.04 | GPL + FOSS | [Docker Hub](https://hub.docker.com/_/ubuntu) (official) | Rebrand if redistributing modified images under Ubuntu name |
| Fedora 40 | GPL + FOSS | [Docker Hub](https://hub.docker.com/_/fedora) (official) | Rebrand if redistributing modified images under Fedora name |
| Debian 12 | GPL / BSD / DFSG | [Docker Hub](https://hub.docker.com/_/debian) (official) | None |
| Rocky Linux 9 | BSD 3-Clause | [Docker Hub](https://hub.docker.com/_/rockylinux) (official) | None |
| AlmaLinux 9 | GPLv2 | [Docker Hub](https://hub.docker.com/_/almalinux) (official) | Standard GPL |
| CentOS Stream 9 | GPLv2 | [Quay.io](https://quay.io/repository/centos/centos) | Standard GPL |

**Note:** CentOS Stream images are hosted on Quay.io (not Docker Hub) since the CentOS
project migrated away from Docker Hub. The image reference `quay.io/centos/centos:stream9`
is the official source.

Trademark restrictions (Ubuntu, Fedora) only apply if you modify the OS and redistribute
it publicly under the original name. Internal and development use is unrestricted.

## How It Works

The Dockerfile uses a build argument to select the base image:

```dockerfile
ARG BASE_IMAGE=ubuntu:22.04
FROM ${BASE_IMAGE}
```

The bootstrap layer detects the package manager and installs minimal prerequisites:

```dockerfile
RUN if command -v apt-get >/dev/null 2>&1; then
        # Debian/Ubuntu path (apt)
    elif command -v dnf >/dev/null 2>&1; then
        # Fedora/Rocky/Alma/CentOS path (dnf)
    elif command -v yum >/dev/null 2>&1; then
        # Legacy CentOS/RHEL path (yum + epel-release)
    fi
```

After bootstrap, `install_dependencies.sh` from tt-metal handles the rest (cmake, clang,
build tools, libraries). The script has its own OS detection logic.

## Adding a New Platform

1. Test the base image manually: `docker run -it <image> bash`
2. Verify that `sudo`, `git`, `wget`, `curl` can be installed via the available package manager
3. Add a preset to `OS_PRESETS` in `build_tt_docker.sh`
4. If the package manager is not apt, dnf, or yum, add a branch to the bootstrap `RUN` in the Dockerfile
5. Run a full build and document any `install_dependencies.sh` failures
