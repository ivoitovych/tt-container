# Manual tt-metal Setup

Scripts for setting up tt-metal development environment without Docker containers.

## setup_tt_metal.sh

Smart setup script that verifies existing state and only performs necessary steps.

### Prerequisites

- Ubuntu 22.04 (or compatible)
- Git with LFS support
- SSH key configured for GitHub (`git@github.com`)
- Sudo access (for installing dependencies)

### Usage

```bash
# Full setup (clone, build, configure)
./setup_tt_metal.sh

# Verify current state only (no changes)
./setup_tt_metal.sh --verify

# Force rebuild tt-metal and tt-train
./setup_tt_metal.sh --rebuild

# Rebuild only tt-train (skip tt-metal build)
./setup_tt_metal.sh --rebuild-tt-train

# Clean build (remove build directories first)
./setup_tt_metal.sh --clean

# Build in Release mode (default: Debug)
./setup_tt_metal.sh --release

# Add a fork remote during setup
./setup_tt_metal.sh --fork-remote myfork=git@github.com:user/tt-metal.git
```

### What It Does

The script performs these steps, skipping any that are already complete:

1. **Clone tt-metal** - Clones from `git@github.com:tenstorrent/tt-metal.git`
2. **Initialize submodules** - Recursive submodule init and update
3. **Pull LFS files** - Downloads large files tracked by Git LFS
4. **Add fork remote** - Optional, if `--fork-remote` specified
5. **Install CMake 3.30+** - If not present
6. **Install dependencies** - Runs `install_dependencies.sh` (includes clang-17)
7. **Setup environment variables** - Adds to `~/.bashrc`:
   - `TT_METAL_HOME`
   - `TT_METAL_RUNTIME_ROOT`
   - `PYTHONPATH`
8. **Create Python venv** - Runs `create_venv.sh`
9. **Build tt-metal** - Runs `build_metal.sh` with ccache
10. **Install ttml** - Installs tt-train Python module via `uv pip`
11. **Build tt-train** - CMake build of tt-train C++ tests

### Environment Variables

The script respects `TT_METAL_HOME` if already set:

```bash
# Use custom location
export TT_METAL_HOME=/path/to/tt-metal
./setup_tt_metal.sh

# Default location (if TT_METAL_HOME not set)
# ~/tt/tt-metal
```

### After Setup

```bash
cd ~/tt/tt-metal  # or $TT_METAL_HOME
source python_env/bin/activate

# Run tt-train tests
./tt-train/build/tests/ttml_tests

# Run specific test
./tt-train/build/tests/ttml_tests --gtest_filter="TestName*"
```

### Build Types

- `--debug` (default): Debug build with symbols, assertions enabled
- `--release`: Optimized build, faster execution

The build directory is `build_Debug/` or `build_Release/`, with `build/` as a symlink to the current type.

### Troubleshooting

**"uv not found"**: The script will install uv via `create_venv.sh`. Ensure `~/.local/bin` and `~/.cargo/bin` are in PATH.

**CMake version too old**: The script installs CMake 3.30.9 to `/opt/cmake` if needed.

**clang-20 not found**: This is a warning, not an error. clang-17 is sufficient for tt-train. clang-20 may be needed for some tt-metal features.

**Build failures after git pull**: Use `--clean` to remove stale build artifacts:
```bash
./setup_tt_metal.sh --clean
```
