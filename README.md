# tt-container

Development environment setup for Tenstorrent tt-metal framework.

Three approaches are provided, from most isolated to most integrated with the host:

| Approach | Use Case | Build Time | Isolation |
|----------|----------|------------|-----------|
| [cached/](cached/) | Reproducible CI/CD, team environments | ~30-60 min (first), fast after | Full |
| [simple/](simple/) | Quick experiments, learning | ~20-30 min | Full |
| [manual/](manual/) | Native performance, existing host setup | ~15-30 min | None |

## Quick Comparison

### cached/ - Production Docker Environment

Full-featured containerized environment with pre-built tt-metal, ccache persistence, and commit hash tracking.

```bash
cd cached/
./build_tt_docker.sh                    # Build image (commit hash auto-detected)
./run_tt_docker.sh                      # Run container (auto-selects latest image)
```

**Best for:**
- Reproducible builds tied to specific commits
- Team environments with shared ccache
- CI/CD pipelines
- Testing multiple tt-metal versions side-by-side

**Features:**
- Pre-built tt-metal (Debug or Release)
- Commit hash in image name for version tracking
- Persistent ccache (5-10x faster rebuilds)
- SSH key forwarding for private repos
- Workspace mounting
- Backup/restore via `docker commit`

See [cached/README.md](cached/README.md) for full documentation.

### simple/ - Minimal Docker Environment

Lightweight container with tt-metal cloned but not pre-built. Good for quick setup when you need to build yourself.

```bash
cd simple/
docker build -t tt-metal-env .          # Build base image
./run_tt_docker.sh                      # Run with hardware access
# Inside container:
cd /workspace/tt-metal
./build_metal.sh --debug --build-all    # Build tt-metal
```

**Best for:**
- Quick experiments
- Learning tt-metal
- When you need to modify build configuration
- Minimal disk usage

**Features:**
- Pre-cloned tt-metal with submodules and LFS
- Python venv ready
- Hardware passthrough configured
- No pre-built binaries (you build as needed)

### manual/ - Native Host Setup

Direct installation on host machine without containers. Maximum performance, full IDE integration.

```bash
cd manual/
./setup_tt_metal.sh                     # Full setup
./setup_tt_metal.sh --verify            # Check current state
./setup_tt_metal.sh --rebuild-tt-train  # Rebuild only tt-train
```

**Best for:**
- Native debugging with full IDE support
- Maximum runtime performance
- When Docker overhead is unacceptable
- Integration with existing host toolchain

**Features:**
- Smart verification (only runs needed steps)
- Respects existing `TT_METAL_HOME`
- Incremental rebuilds
- Debug/Release build types

See [manual/README.md](manual/README.md) for full documentation.

## Prerequisites

### All Approaches

- **Hardware**: Tenstorrent accelerator (Wormhole, Blackhole, etc.)
- **Kernel module**: `sudo modprobe tenstorrent`
- **Device access**: `/dev/tenstorrent` must exist

### Docker Approaches (cached/, simple/)

- Docker 20.10+ with BuildKit
- SSH keys for GitHub (cached/ only, for private repos)
- ~20GB disk space

### Manual Approach

- Ubuntu 22.04 (or compatible)
- Git with LFS support
- Sudo access
- ~30GB disk space

## Hardware Verification

```bash
# Check kernel module
lsmod | grep tenstorrent

# Check device
ls -l /dev/tenstorrent

# Load module if needed
sudo modprobe tenstorrent
```

## Choosing an Approach

```
Need reproducible builds with version tracking?
  └─> cached/

Just want to try tt-metal quickly?
  └─> simple/

Need native performance or full IDE integration?
  └─> manual/

Working in a team with shared resources?
  └─> cached/ (with shared ccache)

CI/CD pipeline?
  └─> cached/ (with --no-build for base image)
```

## License

MIT License. See individual subdirectories for details.

Tenstorrent repositories (tt-metal, tt-smi, etc.) are subject to their own licenses.
