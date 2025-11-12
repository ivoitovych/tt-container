
# Tenstorrent tt-metal Docker Development Environment

A containerized development environment for Tenstorrent's tt-metal framework, providing a reproducible and isolated workspace for hardware development and testing. This repository includes a Dockerfile to set up an Ubuntu 22.04 container with necessary dependencies, tools, and optionally a pre-built tt-metal installation. Two helper scripts are provided: `build_tt_docker.sh` for building the Docker image and `run_tt_docker.sh` for launching the container.

The setup supports cloning private Tenstorrent repositories via SSH, uses ccache for faster compiles, and mounts hardware devices (e.g., `/dev/tenstorrent`) for direct access to Tenstorrent hardware.

## Quick Start

1. **Clone this repository:**
   ```bash
   git clone <your-repo-url>
   cd <repo-directory>
   ```

2. **Load Tenstorrent kernel module (if using hardware):**
   ```bash
   sudo modprobe tenstorrent
   ```

3. **Build a Docker Image:**
   Build a pre-compiled Debug environment:
   ```bash
   ./build_tt_docker.sh
   ```
   This creates an image like `<user>-tt-metal-env-built-debug-eca8b5a8f1:latest` where `eca8b5a8f1` is the commit hash automatically fetched from GitHub.

4. **Run a Container:**
   Launch a container from the built image:
   ```bash
   ./run_tt_docker.sh
   ```
   You'll be dropped into an interactive shell with tt-metal ready to use, Python venv activated, and ccache configured. The script automatically selects the most recently created image.

5. **Backup Your Container (optional):**
   To save your work after making changes, from another terminal:
   ```bash
   docker commit <user>-tt-metal-container <user>-tt-metal-env-built-debug-eca8b5a8f1:backup-2025-11-10-1
   ```

## Overview

- Automated environment setup with all required dependencies.
- Flexible build options for Debug/Release configurations.
- Persistent ccache for faster incremental builds (5-10x speedup on rebuilds).
- Hardware device passthrough for testing on real Tenstorrent accelerators.
- SSH integration for private repository access.
- Mounts for workspaces, tt-kmd, and tt-flash from the host.

## Prerequisites

### Host System Requirements
- Operating System: Linux (Ubuntu 22.04 or compatible).
- Docker: Version 20.10+ with BuildKit support.
- Tenstorrent Hardware (optional): For running on actual devices.
  - Kernel module loaded: `sudo modprobe tenstorrent`.
  - Device accessible at `/dev/tenstorrent`.
- SSH Keys: For GitHub access to private Tenstorrent repositories (typically in `~/.ssh/`).
- Disk Space: ~20GB minimum (more if building with ccache).

### Software Dependencies
- Docker installed and running.
- SSH keys configured for GitHub access (test with `ssh -T git@github.com`).
- Tenstorrent kernel drivers installed (if using hardware).

### Verification
```bash
# Test SSH access to GitHub
ssh -T git@github.com

# Check for Tenstorrent device (if using hardware)
ls -l /dev/tenstorrent

# Verify kernel module (if using hardware)
lsmod | grep tenstorrent
```

## Building the Docker Image

Use `build_tt_docker.sh` to build the image. By default, it builds tt-metal in Debug mode from the `main` branch. The script automatically fetches the commit hash from GitHub and includes it in the image name.

### Usage
```bash
./build_tt_docker.sh [OPTIONS]
```

### Options
- `--no-build` or `--skip-ttmetal`: Skip building tt-metal (creates a base image for manual builds inside the container).
- `--build-type TYPE`: Set build type (`Debug` or `Release`). Default: `Debug`.
- `--branch BRANCH` or `--tt-metal-branch BRANCH`: Specify tt-metal branch or commit hash. Default: `main`.
- `--commit-hash HASH`: Manually specify commit hash (skips auto-fetch from GitHub).
- `--tag-suffix SUFFIX`: Add a custom suffix to the image tag.
- `--force`: Force rebuild even if image for this commit already exists.
- `--ccache-dir DIR`: Host ccache directory. Default: `~/.cache/ccache-docker`.
- `--ssh-key PATH`: Path to SSH keys directory. Default: `~/.ssh`.
- `-h` or `--help`: Show help message.

### Examples
- Default build (Debug mode, main branch):
  ```bash
  ./build_tt_docker.sh
  # Creates: <user>-tt-metal-env-built-debug-eca8b5a8f1:latest
  ```

- Release build:
  ```bash
  ./build_tt_docker.sh --build-type Release
  # Creates: <user>-tt-metal-env-built-release-eca8b5a8f1:latest
  ```

- Base image (no pre-built tt-metal):
  ```bash
  ./build_tt_docker.sh --no-build
  # Creates: <user>-tt-metal-env-base-eca8b5a8f1:latest
  ```

- Specific branch:
  ```bash
  ./build_tt_docker.sh --branch feature/my-branch
  # Fetches commit hash for that branch automatically
  # Creates: <user>-tt-metal-env-built-debug-a1b2c3d4e5:latest
  ```

- Force rebuild of existing image:
  ```bash
  ./build_tt_docker.sh --force
  # Replaces the 'latest' tag of existing image for this commit
  ```

- Advanced configuration:
  ```bash
  ./build_tt_docker.sh \
    --build-type Release \
    --branch v1.2.3 \
    --tag-suffix custom \
    --ccache-dir /path/to/ccache \
    --ssh-key /path/to/ssh/keys
  ```

**Note:** If you try to build an image for a commit that already exists, the script will show an error with options to use the existing image, backup and rebuild, or build a different commit.

The script generates an image name including the commit hash (e.g., `user-tt-metal-env-built-debug-eca8b5a8f1`) to prevent conflicts when working with multiple commits.

## Running the Container

Use `run_tt_docker.sh` to launch the container. It mounts necessary devices and volumes for hardware access and development. If no image is specified, it automatically selects the most recently created image.

### Usage
```bash
./run_tt_docker.sh [OPTIONS]
```

### Options
- `--image TAG`: Docker image to use (repository name or repository:tag). Examples: `user-tt-metal-env-built-debug-eca8b5a8f1` or `user-tt-metal-env-built-debug-eca8b5a8f1:backup-2025-11-10-1`.
- `--name NAME`: Container name. Default: `<user>-tt-metal-container`.
- `--ccache-dir DIR`: Host ccache directory. Default: `~/.cache/ccache-docker`.
- `--no-ccache`: Don't mount ccache.
- `--mount-workspace [DIR]`: Mount a host directory as `/workspace/user`. Default DIR: `./workspace`.
- `--ssh-key PATH`: Path to SSH keys directory. Default: `~/.ssh`.
- `--no-ssh`: Don't mount SSH keys.
- `-h` or `--help`: Show help message.

### Examples
- Default run (auto-selects most recent image):
  ```bash
  ./run_tt_docker.sh
  ```

- Run specific image:
  ```bash
  ./run_tt_docker.sh --image <user>-tt-metal-env-built-debug-eca8b5a8f1
  ```

- Run from a backup:
  ```bash
  ./run_tt_docker.sh --image <user>-tt-metal-env-built-debug-eca8b5a8f1:backup-2025-11-10-1
  ```

- With workspace mount:
  ```bash
  ./run_tt_docker.sh --mount-workspace /path/to/my/workspace
  ```

- Custom configuration:
  ```bash
  ./run_tt_docker.sh \
    --image myuser-tt-metal-env-built-release-abc123def4 \
    --name my-dev-container \
    --mount-workspace ~/tt-projects
  ```

Inside the container:
- Python venv is activated (`/workspace/tt-metal/python_env`).
- tt-metal is at `/workspace/tt-metal` (if built).
- tt-smi is installed and available.
- Use `tt-smi` or other tools to interact with hardware.

### Backup Workflow
To save your container state with all installed packages and changes:
```bash
# From another terminal while container is running
docker commit <user>-tt-metal-container <user>-tt-metal-env-built-debug-eca8b5a8f1:backup-2025-11-10-1

# Later, run from that backup
./run_tt_docker.sh --image <user>-tt-metal-env-built-debug-eca8b5a8f1:backup-2025-11-10-1
```

The `latest` tag is your fresh build, and `backup-YYYY-MM-DD-N` tags are your saved container states.

## Dockerfile Overview

The Dockerfile:
- Uses Ubuntu 22.04 as base.
- Installs dependencies (build tools, Python, libraries like libnuma-dev, cargo).
- Clones Tenstorrent repos (`tt-system-tools`, `tt-smi`, `tt-metal`) via SSH.
- Optionally builds tt-metal with ccache.
- Installs tt-smi.
- Sets up an entrypoint for venv activation, ccache, and SSH setup.

### Build Arguments
- `BUILD_TTMETAL` (true/false): Build tt-metal? Default: true.
- `BUILD_TYPE` (Debug/Release): Build type. Default: Debug.
- `TT_METAL_BRANCH` (branch/commit): tt-metal version. Default: main.

### Build Arguments
- `BUILD_TTMETAL` (true/false): Build tt-metal? Default: true.
- `BUILD_TYPE` (Debug/Release): Build type. Default: Debug.
- `CHECKOUT_REF` (branch/tag/commit): What to checkout in the container. Default: main.
- `EXPECTED_COMMIT_HASH`: The commit hash that should result from the checkout (for verification).
- `REF_TYPE` (branch/tag/commit): Type of reference being checked out.

**Note:** The build script automatically sets these values. `CHECKOUT_REF` preserves branch/tag names to maintain tracking, while `EXPECTED_COMMIT_HASH` ensures the checkout results in the correct commit.

## Container Features

### Included Software
- Ubuntu 22.04 base system.
- tt-metal framework (cloned and optionally pre-built).
- tt-smi and tt-system-tools utilities.
- CMake 3.30.9 (required for tt-train).
- Python 3 with virtual environment.
- Development tools: GCC, Clang, LLVM, Ninja, ccache.
- Libraries: numpy, libstdc++-12-dev, libmpfr-dev, libnuma-dev, libtbb-dev, etc.
- Documentation tools: Doxygen, Pandoc, LaTeX, Graphviz.

### Directory Structure
```
/workspace/
├── tt-metal/          # Main tt-metal repository
│   └── python_env/    # Python virtual environment (auto-activated)
├── tt-smi/            # SMI tools repository
├── tt-system-tools/   # System utilities repository
└── user/              # Your mounted workspace (if --mount-workspace used)
```

### Environment Variables
Automatically configured:
- `TT_METAL_HOME=/workspace/tt-metal`
- `PYTHONPATH=/workspace/tt-metal`
- `ARCH_NAME=wormhole_b0`
- `CCACHE_DIR=/ccache`
- Python virtual environment activated on startup.

### Hardware Access
- Privileged mode for full hardware access.
- Device passthrough for `/dev/tenstorrent`.
- Kernel module access via host `/lib/modules`.
- Huge pages mounted for performance.

## Common Workflows

### Building tt-metal Inside Container
If using a base image or rebuilding:
```bash
cd /workspace/tt-metal

# Debug build
./build_metal.sh --debug --build-all --enable-ccache

# Release build
./build_metal.sh --release --build-all --enable-ccache
```

### Running Tests
```bash
cd /workspace/tt-metal
pytest tests/
```

### Using tt-smi
```bash
source /workspace/tt-smi/.venv/bin/activate
tt-smi
```

### Checking Hardware
```bash
# Inside container
ls -l /dev/tenstorrent

# Check system info
tt-smi --info
```

### Persisting Work
Mount a workspace to save work between runs:
```bash
./run_tt_docker.sh --mount-workspace ~/tt-projects

# Inside container: work in /workspace/user/
cd /workspace/user
```

## Advanced Usage

### Multiple Containers
Run multiple containers with different configurations:
```bash
# Terminal 1: Debug environment
./run_tt_docker.sh --name debug-env --image <user>-tt-metal-env-built-debug-abc123

# Terminal 2: Release environment
./run_tt_docker.sh --name release-env --image <user>-tt-metal-env-built-release-abc123

# Terminal 3: Different commit
./run_tt_docker.sh --name test-env --image <user>-tt-metal-env-built-debug-def456
```

### Custom Workspace Structure
```bash
# Create organized workspace
mkdir -p ~/tt-workspace/{projects,data,models}

# Mount it
./run_tt_docker.sh --mount-workspace ~/tt-workspace
```

### Debugging Build Issues
```bash
# Verbose build output
export BUILDKIT_PROGRESS=plain
./build_tt_docker.sh

# Interactive container for debugging
docker run -it --rm <image-tag> /bin/bash
```

### Sharing Ccache Across Teams
```bash
# Use a shared network location for ccache
./build_tt_docker.sh --ccache-dir /shared/team/ccache
./run_tt_docker.sh --ccache-dir /shared/team/ccache
```

## Ccache Configuration

ccache is shared across containers for 5-10x faster rebuilds:
- Host location: `~/.cache/ccache-docker`
- Container mount: `/ccache`
- Size limit: 10GB
- Benefit: Dramatically faster incremental builds

### Ccache Commands
```bash
# Check statistics
ccache -s

# Clear cache
ccache -C

# Set maximum size
ccache -M 20G

# Zero statistics (useful for benchmarking)
ccache -z
```

## Image Tags

Images are named with the pattern `<user>-tt-metal-env-<type>-<commit-hash>:<tag>`:
- Repository includes commit hash: `<user>-tt-metal-env-built-debug-eca8b5a8f1`
- `latest` tag: Fresh build from Dockerfile
- `backup-YYYY-MM-DD-N` tags: Saved container states via `docker commit`

Examples:
- `ivoitovych-tt-metal-env-built-debug-eca8b5a8f1:latest` - Fresh Debug build
- `ivoitovych-tt-metal-env-built-release-eca8b5a8f1:latest` - Fresh Release build
- `ivoitovych-tt-metal-env-base-eca8b5a8f1:latest` - Base image without pre-built tt-metal
- `ivoitovych-tt-metal-env-built-debug-eca8b5a8f1:backup-2025-11-10-1` - Saved container state

View all available images:
```bash
docker images | grep tt-metal-env
```

## Performance Tips

1. Use ccache (default) for faster rebuilds—expect 5-10x speedup on incremental builds.
2. Prefer pre-built images for quicker container startup and immediate development.
3. Mount persistent workspaces to avoid re-downloading dependencies and preserve work.
4. Use Release builds for production testing (faster runtime performance).
5. Share ccache across team members to leverage collective build cache.

## Troubleshooting

### Device Not Found
**Problem**: "Warning: /dev/tenstorrent device not found!"
**Solution**:
```bash
# Load kernel module on host
sudo modprobe tenstorrent

# Verify device exists
ls -l /dev/tenstorrent
```

### SSH Key Issues
**Problem**: Build fails with "Permission denied (publickey)".
**Solutions**:
```bash
# Verify SSH keys exist
ls -la ~/.ssh/

# Test GitHub access
ssh -T git@github.com

# Add key to SSH agent
eval $(ssh-agent -s)
ssh-add ~/.ssh/id_rsa
```

### Image Not Found
**Problem**: "Error: Docker image not found!"
**Solution**:
```bash
# List available images
docker images | grep tt-metal-env

# Build image if needed
./build_tt_docker.sh
```

### Image Already Exists
**Problem**: "ERROR: Image repository already exists. Build cancelled."
**Solution**: You've already built an image for this commit. Options:
```bash
# Use existing image
./run_tt_docker.sh

# Build different commit
./build_tt_docker.sh --branch other-branch

# Force rebuild (replaces 'latest' tag)
./build_tt_docker.sh --force

# Remove existing images for this commit
docker rmi $(docker images <repository-name> -q)
```

### Build Fails
**Problem**: Docker build errors.
**Solutions**:
- Check disk space: `df -h`
- Clear Docker cache: `docker system prune -a`
- Verify SSH keys are accessible
- Check network connectivity
- Review build logs for specific errors

### Kernel Module Not Loaded
**Problem**: Warning about tenstorrent kernel module not loaded.
**Solution**:
```bash
# Load module on host
sudo modprobe tenstorrent

# Verify it's loaded
lsmod | grep tenstorrent

# Make it persistent across reboots
echo "tenstorrent" | sudo tee -a /etc/modules
```

### Ccache Not Working
**Problem**: Builds are slow despite ccache.
**Solutions**:
```bash
# Check ccache is mounted
ls -la /ccache

# Verify host directory permissions
ls -la ~/.cache/ccache-docker
chmod 755 ~/.cache/ccache-docker

# Check ccache statistics
ccache -s

# Ensure ccache is in PATH
echo $PATH | grep ccache
```

### Permission Issues
**Problem**: Cannot write to mounted directories.
**Solution**: Container runs as root by default. Ensure host directories have appropriate permissions:
```bash
chmod 755 ~/.cache/ccache-docker
chmod 755 /path/to/workspace
```

For more details, check Docker logs or run with `DOCKER_BUILDKIT=1` for verbose output.

## Contributing

When modifying the Dockerfile or scripts:
1. Test both base and built image configurations.
2. Verify ccache functionality with incremental builds.
3. Ensure SSH key mounting works correctly.
4. Test with and without hardware devices.
5. Update documentation for any new features or options.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details. (Note: Add a LICENSE file if needed.)

Note: Tenstorrent repositories (tt-metal, tt-smi, tt-system-tools) are subject to their own licenses.

## Additional Resources

- [Tenstorrent tt-metal Repository](https://github.com/tenstorrent/tt-metal)
- [Tenstorrent Documentation](https://docs.tenstorrent.com/)
- [Docker BuildKit Documentation](https://docs.docker.com/build/buildkit/)

