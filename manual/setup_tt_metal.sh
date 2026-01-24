#!/bin/bash
#
# Smart setup script for tt-metal development environment
# Verifies existing state and only performs necessary steps
#
# Usage:
#   ./setup_tt_metal.sh              # Full setup with verification
#   ./setup_tt_metal.sh --verify     # Verify only, no changes
#   ./setup_tt_metal.sh --rebuild    # Force rebuild tt-metal and tt-train
#   ./setup_tt_metal.sh --clean      # Clean and rebuild
#

set -e

# Configuration - derive from environment if set
if [[ -n "$TT_METAL_HOME" ]]; then
    TT_METAL_DIR="$TT_METAL_HOME"
    TT_DIR="$(dirname "$TT_METAL_HOME")"
else
    TT_DIR="${HOME}/tt"
    TT_METAL_DIR="${TT_DIR}/tt-metal"
fi
BUILD_TYPE="${BUILD_TYPE:-Debug}"
VERIFY_ONLY=false
FORCE_REBUILD=false
CLEAN_BUILD=false
FORK_REMOTE_NAME=""
FORK_REMOTE_URL=""
FRESH_CLONE=false  # Track if we just cloned
REBUILD_TT_TRAIN_ONLY=false  # Only rebuild tt-train/ttml
FORCE_DEPS=false  # Force running install_dependencies.sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verify)
            VERIFY_ONLY=true
            shift
            ;;
        --rebuild)
            FORCE_REBUILD=true
            shift
            ;;
        --clean)
            CLEAN_BUILD=true
            FORCE_REBUILD=true
            shift
            ;;
        --release)
            BUILD_TYPE="Release"
            shift
            ;;
        --debug)
            BUILD_TYPE="Debug"
            shift
            ;;
        --fork-remote)
            # Format: name=url, e.g., myfork=git@github-alt:user/tt-metal.git
            FORK_REMOTE_NAME="${2%%=*}"
            FORK_REMOTE_URL="${2#*=}"
            shift 2
            ;;
        --rebuild-tt-train)
            REBUILD_TT_TRAIN_ONLY=true
            FORCE_REBUILD=true
            shift
            ;;
        --force-deps)
            FORCE_DEPS=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --verify              Verify current state only, make no changes"
            echo "  --rebuild             Force rebuild of tt-metal and tt-train"
            echo "  --clean               Clean build directories and rebuild"
            echo "  --release             Build in Release mode (default: Debug)"
            echo "  --debug               Build in Debug mode"
            echo "  --fork-remote NAME=URL  Add a fork remote (e.g., myfork=git@github-alt:user/tt-metal.git)"
            echo "  --rebuild-tt-train    Rebuild tt-train and ttml only (skip tt-metal build)"
            echo "  --force-deps          Force running install_dependencies.sh"
            echo "  -h, --help            Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

# Check functions return 0 if OK, 1 if needs work
check_tt_metal_clone() {
    [[ -d "${TT_METAL_DIR}/.git" ]]
}

check_submodules() {
    cd "${TT_METAL_DIR}"
    # Check if submodules are initialized (no lines starting with -)
    ! git submodule status --recursive | grep -q "^-"
}

check_lfs() {
    cd "${TT_METAL_DIR}"
    # Check if LFS files are pulled (no lines starting with -)
    ! git lfs ls-files 2>/dev/null | head -5 | grep -q "^-"
}

check_fork_remote() {
    [[ -z "$FORK_REMOTE_NAME" ]] && return 0  # Skip if not configured
    cd "${TT_METAL_DIR}"
    git remote | grep -q "^${FORK_REMOTE_NAME}$"
}

check_cmake() {
    if ! command -v cmake &> /dev/null; then
        return 1
    fi
    local version=$(cmake --version | head -1 | sed 's/cmake version //')
    local major=$(echo "$version" | cut -d. -f1)
    local minor=$(echo "$version" | cut -d. -f2)
    [[ "$major" -gt 3 ]] || [[ "$major" -eq 3 && "$minor" -ge 30 ]]
}

check_clang17() {
    command -v clang++-17 &> /dev/null
}

check_clang20() {
    command -v clang++-20 &> /dev/null
}

check_python_venv() {
    [[ -f "${TT_METAL_DIR}/python_env/bin/activate" ]]
}

check_uv() {
    command -v uv &> /dev/null
}

check_tt_metal_build() {
    # Check for build_$BUILD_TYPE directory (build/ is just a symlink)
    local build_dir="${TT_METAL_DIR}/build_${BUILD_TYPE}"
    [[ -d "$build_dir" ]] && find "$build_dir" -name "*.so" 2>/dev/null | grep -q .
}

check_tt_train_build() {
    [[ -f "${TT_METAL_DIR}/tt-train/build/tests/ttml_tests" ]]
}

check_ttml_installed() {
    [[ -f "${TT_METAL_DIR}/python_env/bin/python" ]] || return 1
    # Use venv's python directly
    "${TT_METAL_DIR}/python_env/bin/python" -c "import ttml" 2>/dev/null
}

check_env_vars() {
    # Check if env vars are set in current session
    [[ -n "$TT_METAL_HOME" ]] || return 1
    [[ -n "$TT_METAL_RUNTIME_ROOT" ]] || return 1
    [[ -n "$PYTHONPATH" ]] || return 1

    # Check if they point to the expected location
    [[ "$TT_METAL_HOME" == "$TT_METAL_DIR" ]] || return 1
    [[ "$TT_METAL_RUNTIME_ROOT" == "$TT_METAL_DIR" ]] || return 1

    # PYTHONPATH may contain multiple paths, check if TT_METAL_DIR is included
    [[ ":$PYTHONPATH:" == *":$TT_METAL_DIR:"* ]] || [[ "$PYTHONPATH" == "$TT_METAL_DIR" ]] || return 1

    return 0
}

# Action functions
clone_tt_metal() {
    log_step "Cloning tt-metal (this may take several minutes)"
    cd "${TT_DIR}"
    git clone --progress --recurse-submodules git@github.com:tenstorrent/tt-metal.git
    cd tt-metal
    log_info "Pulling LFS files..."
    git lfs pull
    log_info "Pulling LFS files in submodules..."
    git submodule foreach --recursive "git lfs pull"
    FRESH_CLONE=true
}

init_submodules() {
    log_step "Initializing submodules"
    cd "${TT_METAL_DIR}"
    git submodule sync --recursive
    git submodule update --init --recursive
}

pull_lfs() {
    log_step "Pulling LFS files"
    cd "${TT_METAL_DIR}"
    git lfs pull
    git submodule foreach --recursive "git lfs pull"
}

add_fork_remote() {
    log_step "Adding ${FORK_REMOTE_NAME} remote"
    cd "${TT_METAL_DIR}"
    git remote add "${FORK_REMOTE_NAME}" "${FORK_REMOTE_URL}"
    git fetch "${FORK_REMOTE_NAME}"
}

install_cmake() {
    log_step "Installing CMake 3.30.9"
    local tmp_dir=$(mktemp -d)
    cd "$tmp_dir"
    wget https://github.com/Kitware/CMake/releases/download/v3.30.9/cmake-3.30.9-linux-x86_64.tar.gz
    tar -xzf cmake-3.30.9-linux-x86_64.tar.gz
    sudo mv cmake-3.30.9-linux-x86_64 /opt/cmake
    rm -rf "$tmp_dir"

    if ! grep -q '/opt/cmake/bin' ~/.bashrc; then
        echo 'export PATH=/opt/cmake/bin:$PATH' >> ~/.bashrc
    fi
    export PATH=/opt/cmake/bin:$PATH
}

run_install_dependencies() {
    log_step "Running install_dependencies.sh"
    cd "${TT_METAL_DIR}"
    sudo ./install_dependencies.sh
}

create_python_venv() {
    log_step "Creating Python virtual environment"
    cd "${TT_METAL_DIR}"
    ./create_venv.sh
}

setup_env_vars() {
    log_step "Setting up environment variables"

    # Set in current session
    export TT_METAL_HOME="$TT_METAL_DIR"
    export TT_METAL_RUNTIME_ROOT="$TT_METAL_DIR"
    export PYTHONPATH="$TT_METAL_DIR"

    # Check if already in .bashrc with correct value
    local bashrc_ok=true

    if grep -q "^export TT_METAL_HOME=" ~/.bashrc 2>/dev/null; then
        local existing=$(grep "^export TT_METAL_HOME=" ~/.bashrc | tail -1 | cut -d= -f2-)
        # Expand $HOME in the existing value for comparison
        existing=$(eval echo "$existing" 2>/dev/null || echo "$existing")
        if [[ "$existing" != "$TT_METAL_DIR" ]]; then
            log_warn "TT_METAL_HOME in .bashrc differs: $existing vs $TT_METAL_DIR"
            bashrc_ok=false
        fi
    else
        bashrc_ok=false
    fi

    if [[ "$bashrc_ok" == "false" ]]; then
        log_info "Adding environment variables to ~/.bashrc"
        # Use the actual path, not $HOME, to avoid issues
        cat >> ~/.bashrc << EOF

# tt-metal environment (added by setup_tt_metal.sh)
export TT_METAL_HOME=${TT_METAL_DIR}
export TT_METAL_RUNTIME_ROOT=\$TT_METAL_HOME
export PYTHONPATH=\$TT_METAL_HOME
EOF
    fi
}

build_tt_metal() {
    log_step "Building tt-metal (${BUILD_TYPE})"
    cd "${TT_METAL_DIR}"

    if [[ "$CLEAN_BUILD" == "true" ]]; then
        # build/ is a symlink to build_$BUILD_TYPE, remove the actual directory
        log_info "Cleaning build_${BUILD_TYPE} directory..."
        rm -rf "build_${BUILD_TYPE}"
        rm -f build  # Remove symlink too
    fi

    local build_flag=$(echo "${BUILD_TYPE}" | tr '[:upper:]' '[:lower:]')
    ./build_metal.sh --${build_flag} --build-all --enable-ccache
}

build_tt_train() {
    log_step "Building tt-train (${BUILD_TYPE})"
    cd "${TT_METAL_DIR}/tt-train"

    if [[ "$CLEAN_BUILD" == "true" ]]; then
        log_info "Cleaning build directory..."
        rm -rf build/
    fi

    # Use system Python (has dev headers), not uv-managed Python
    cmake -DCMAKE_BUILD_TYPE=${BUILD_TYPE} \
          -DCMAKE_C_COMPILER_LAUNCHER=ccache \
          -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
          -DPython_ROOT_DIR=/usr \
          -B build -GNinja
    cmake --build build --config ${BUILD_TYPE}
}

install_ttml() {
    log_step "Installing ttml Python module"
    cd "${TT_METAL_DIR}"
    # Ensure uv is in PATH (may have been installed by create_venv.sh)
    export PATH="${HOME}/.local/bin:${HOME}/.cargo/bin:${PATH}"
    # Use uv pip (uv-managed venvs don't have pip)
    source python_env/bin/activate
    uv pip install -e tt-train
    deactivate
}

# Main verification and setup
main() {
    log_step "tt-metal Setup Script"
    echo "TT_DIR: ${TT_DIR}"
    echo "TT_METAL_DIR: ${TT_METAL_DIR}"
    echo "Build type: ${BUILD_TYPE}"
    echo "Verify only: ${VERIFY_ONLY}"
    echo "Force rebuild: ${FORCE_REBUILD}"
    if [[ "$REBUILD_TT_TRAIN_ONLY" == "true" ]]; then
        echo "Rebuild tt-train only: true"
    fi
    if [[ -n "$FORK_REMOTE_NAME" ]]; then
        echo "Fork remote: ${FORK_REMOTE_NAME}=${FORK_REMOTE_URL}"
    fi
    echo ""

    # Step 1: Check tt-metal clone
    log_info "Checking tt-metal clone..."
    if check_tt_metal_clone; then
        log_success "tt-metal repository exists at ${TT_METAL_DIR}"
    else
        log_info "tt-metal not found - will clone"
        if [[ "$VERIFY_ONLY" == "true" ]]; then
            log_error "Run without --verify to clone"
            exit 1
        fi
        clone_tt_metal
    fi

    # Step 2: Check submodules
    log_info "Checking submodules..."
    if check_submodules; then
        log_success "Submodules initialized"
    else
        log_info "Initializing submodules..."
        if [[ "$VERIFY_ONLY" == "true" ]]; then
            log_error "Run without --verify to initialize submodules"
            exit 1
        fi
        init_submodules
    fi

    # Step 3: Check LFS
    log_info "Checking LFS files..."
    if check_lfs; then
        log_success "LFS files pulled"
    else
        log_info "Pulling LFS files..."
        if [[ "$VERIFY_ONLY" == "true" ]]; then
            log_error "Run without --verify to pull LFS files"
            exit 1
        fi
        pull_lfs
    fi

    # Step 4: Check fork remote (if configured)
    if [[ -n "$FORK_REMOTE_NAME" ]]; then
        log_info "Checking ${FORK_REMOTE_NAME} remote..."
        if check_fork_remote; then
            log_success "${FORK_REMOTE_NAME} remote configured"
        else
            log_warn "${FORK_REMOTE_NAME} remote not configured"
            if [[ "$VERIFY_ONLY" == "true" ]]; then
                log_error "Run without --verify to add ${FORK_REMOTE_NAME} remote"
                exit 1
            fi
            add_fork_remote
        fi
    fi

    # Step 5: Check CMake
    log_info "Checking CMake >= 3.30..."
    if check_cmake; then
        log_success "CMake $(cmake --version | head -1 | sed 's/cmake version //')"
    else
        log_warn "CMake >= 3.30 not found"
        if [[ "$VERIFY_ONLY" == "true" ]]; then
            log_error "Run without --verify to install CMake"
            exit 1
        fi
        install_cmake
    fi

    # Step 6: Run install_dependencies.sh
    # Always run on fresh clone or with --force-deps
    # install_dependencies.sh installs many packages (clang-17, clang-20,
    # libc++-17-dev, libhwloc-dev, libtbb-dev, etc.) and we can't reliably
    # check for all of them
    if [[ "$FRESH_CLONE" == "true" ]] || [[ "$FORCE_DEPS" == "true" ]]; then
        if [[ "$FRESH_CLONE" == "true" ]]; then
            log_info "Running install_dependencies.sh (fresh clone)"
        else
            log_info "Running install_dependencies.sh (--force-deps)"
        fi
        if [[ "$VERIFY_ONLY" == "true" ]]; then
            log_error "Run without --verify to install dependencies"
            exit 1
        fi
        run_install_dependencies
    else
        # For existing clones, check if key dependencies are present
        log_info "Checking dependencies..."
        if check_clang17 && check_clang20; then
            log_success "clang-17 and clang-20 installed"
        else
            log_warn "Some dependencies missing - running install_dependencies.sh"
            if [[ "$VERIFY_ONLY" == "true" ]]; then
                log_error "Run without --verify to install dependencies"
                exit 1
            fi
            run_install_dependencies
        fi
    fi

    # Step 8: Check environment variables
    log_info "Checking environment variables..."
    if check_env_vars; then
        log_success "Environment variables configured in ~/.bashrc"
    else
        log_warn "Environment variables not set"
        if [[ "$VERIFY_ONLY" == "true" ]]; then
            log_error "Run without --verify to setup env vars"
            exit 1
        fi
        setup_env_vars
    fi

    # Step 9: Check uv (required for venv and package installation)
    log_info "Checking uv..."
    if check_uv; then
        log_success "uv $(uv --version 2>/dev/null | cut -d' ' -f2)"
    else
        log_warn "uv not found - will be installed by create_venv.sh"
    fi

    # Step 10: Check Python venv
    log_info "Checking Python virtual environment..."
    if check_python_venv; then
        log_success "Python venv exists"
    else
        if [[ "$FRESH_CLONE" == "true" ]]; then
            log_info "Creating Python venv (fresh clone)"
        else
            log_warn "Python venv needs creation"
        fi
        if [[ "$VERIFY_ONLY" == "true" ]]; then
            log_error "Run without --verify to create venv"
            exit 1
        fi
        create_python_venv
    fi

    # Step 11: Check tt-metal build
    if [[ "$REBUILD_TT_TRAIN_ONLY" == "true" ]]; then
        log_info "Skipping tt-metal build (--rebuild-tt-train)"
    else
        log_info "Checking tt-metal build..."
        if check_tt_metal_build && [[ "$FORCE_REBUILD" == "false" ]]; then
            log_success "tt-metal is built"
        else
            if [[ "$FORCE_REBUILD" == "true" ]]; then
                log_info "Rebuilding tt-metal (forced)"
            elif [[ "$FRESH_CLONE" == "true" ]]; then
                log_info "Building tt-metal (fresh clone)"
            else
                log_warn "tt-metal needs building"
            fi
            if [[ "$VERIFY_ONLY" == "true" ]]; then
                log_error "Run without --verify to build"
                exit 1
            fi
            build_tt_metal
        fi
    fi

    # Step 12: Check ttml installation
    log_info "Checking ttml Python module..."
    if check_ttml_installed && [[ "$FORCE_REBUILD" == "false" ]]; then
        log_success "ttml module installed"
    else
        if [[ "$FORCE_REBUILD" == "true" ]]; then
            log_info "Reinstalling ttml (forced)"
        elif [[ "$FRESH_CLONE" == "true" ]]; then
            log_info "Installing ttml (fresh clone)"
        else
            log_warn "ttml module needs installation"
        fi
        if [[ "$VERIFY_ONLY" == "true" ]]; then
            log_error "Run without --verify to install ttml"
            exit 1
        fi
        install_ttml
    fi

    # Step 13: Check tt-train build
    log_info "Checking tt-train build..."
    if check_tt_train_build && [[ "$FORCE_REBUILD" == "false" ]]; then
        log_success "tt-train is built"
    else
        if [[ "$FORCE_REBUILD" == "true" ]]; then
            log_info "Rebuilding tt-train (forced)"
        elif [[ "$FRESH_CLONE" == "true" ]]; then
            log_info "Building tt-train (fresh clone)"
        else
            log_warn "tt-train needs building"
        fi
        if [[ "$VERIFY_ONLY" == "true" ]]; then
            log_error "Run without --verify to build"
            exit 1
        fi
        build_tt_train
    fi

    # Summary
    log_step "Setup Complete"
    echo ""
    echo "tt-metal: ${TT_METAL_DIR}"
    echo "Build type: ${BUILD_TYPE}"
    echo "Commit: $(cd ${TT_METAL_DIR} && git rev-parse --short HEAD)"
    echo ""
    echo "To activate the environment:"
    echo "  cd ${TT_METAL_DIR}"
    echo "  source python_env/bin/activate"
    echo ""
    echo "To run tt-train tests:"
    echo "  ${TT_METAL_DIR}/tt-train/build/tests/ttml_tests"
    echo ""
    echo "ccache stats:"
    ccache -s 2>/dev/null | head -5 || true
}

main "$@"
