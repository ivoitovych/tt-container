#!/bin/bash

# OS platform presets
# Main:         ubuntu:22.04, ubuntu:24.04, fedora:40, fedora:42
# Experimental: debian:12, almalinux:10, oraclelinux:10
# Note: rockylinux:10 not yet available as Docker image (as of March 2026)
declare -A OS_PRESETS=(
    [ubuntu2204]="ubuntu:22.04"
    [ubuntu2404]="ubuntu:24.04"
    [fedora40]="fedora:40"
    [fedora42]="fedora:42"
    [debian12]="debian:12"
    [alma10]="almalinux:10"
    [oracle10]="oraclelinux:10"
)

# Parse command line arguments
BUILD_TTMETAL=true  # Default to building tt-metal
BUILD_TYPE="Debug"
IMAGE_TAG_SUFFIX=""
CCACHE_HOST_DIR="${HOME}/.cache/ccache-docker"
SSH_KEY_PATH="${HOME}/.ssh"
TT_METAL_BRANCH="main"
COMMIT_HASH=""  # Will be fetched from GitHub
FORCE_BUILD=false
TT_TRAIN_COMPILER="none"  # Override tt-train compiler: none, clang-N, gcc-N
MERGE_BRANCHES=()  # Additional branches to merge after checkout
SKIP_TT_TRAIN_STANDALONE=false  # Skip standalone tt-train builds (pip install + cmake)
BASE_IMAGE="ubuntu:22.04"
OS_LABEL="ubuntu2204"
COMPILER=""  # Compiler selection for build_metal.sh and install_dependencies.sh
NO_CACHE=false  # Pass --no-cache to docker build

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-build)
            BUILD_TTMETAL=false
            shift
            ;;
        --skip-ttmetal)
            BUILD_TTMETAL=false
            shift
            ;;
        --build-type)
            BUILD_TYPE="$2"
            shift 2
            ;;
        --branch|--tt-metal-branch)
            TT_METAL_BRANCH="$2"
            shift 2
            ;;
        --commit-hash)
            COMMIT_HASH="$2"
            shift 2
            ;;
        --tag-suffix)
            IMAGE_TAG_SUFFIX="$2"
            shift 2
            ;;
        --ccache-dir)
            CCACHE_HOST_DIR="$2"
            shift 2
            ;;
        --ssh-key)
            SSH_KEY_PATH="$2"
            shift 2
            ;;
        --os)
            OS_LABEL="$2"
            if [ -n "${OS_PRESETS[$OS_LABEL]+x}" ]; then
                BASE_IMAGE="${OS_PRESETS[$OS_LABEL]}"
            else
                echo "ERROR: Unknown OS preset: $OS_LABEL"
                echo "Available presets:"
                echo "  Main:         ubuntu2204 (default), ubuntu2404, fedora40, fedora42"
                echo "  Experimental: debian12, alma10, oracle10"
                exit 1
            fi
            shift 2
            ;;
        --base-image)
            BASE_IMAGE="$2"
            # Derive label from image name (replace : and / with -)
            OS_LABEL=$(echo "$2" | tr ':/' '-')
            shift 2
            ;;
        --force)
            FORCE_BUILD=true
            shift
            ;;
        --no-cache)
            NO_CACHE=true
            shift
            ;;
        --tt-train-compiler)
            TT_TRAIN_COMPILER="$2"
            shift 2
            ;;
        --merge-branch)
            MERGE_BRANCHES+=("$2")
            shift 2
            ;;
        --skip-tt-train-standalone)
            SKIP_TT_TRAIN_STANDALONE=true
            shift
            ;;
        --compiler)
            COMPILER="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --os PRESET         OS platform preset [default: ubuntu2204]"
            echo "                      Main:         ubuntu2204, ubuntu2404, fedora40"
            echo "                      Experimental: debian12, alma10"
            echo "  --base-image IMAGE  Custom base image (overrides --os)"
            echo "  --no-build          Don't build tt-metal during image creation"
            echo "  --skip-ttmetal      Same as --no-build"
            echo "  --build-type TYPE   Build type (Debug/Release) [default: Debug]"
            echo "  --branch BRANCH     tt-metal branch or commit hash [default: main]"
            echo "  --commit-hash HASH  Specify commit hash directly (skips auto-fetch)"
            echo "  --tag-suffix SUFFIX Custom suffix for image tag"
            echo "  --ccache-dir DIR    Host ccache directory [default: ~/.cache/ccache-docker]"
            echo "  --ssh-key PATH      Path to SSH keys directory [default: ~/.ssh]"
            echo "  --force             Force rebuild even if image exists"
            echo "  --no-cache          Disable Docker layer caching (fresh build)"
            echo "  --tt-train-compiler COMPILER  Override tt-train compiler: none, clang-N, gcc-N [default: none]"
            echo "  --merge-branch BRANCH         Merge branch after checkout (repeatable). Use user/repo:branch for forks"
            echo "  --skip-tt-train-standalone    Skip standalone tt-train builds (pip install + cmake)"
            echo "  --compiler COMPILER           Compiler for tt-metal build: clang-20 (default), clang, gcc, gcc-12, gcc-14, clang-20-libcpp"
            echo "  -h, --help          Show this help message"
            echo ""
            echo "Default: Builds tt-metal in Debug mode from main branch on Ubuntu 22.04"
            echo "Image name: <user>-tt-metal-env-<os>-built-<type>-<hash>:latest"
            echo ""
            echo "Examples:"
            echo "  $0 --branch main                                          # Build from main"
            echo "  $0 --branch main --merge-branch user/feature-branch       # Build main + merge a branch"
            echo "  $0 --branch main --tt-train-compiler clang-17             # Build with clang-17 for tt-train"
            echo "  $0 --branch main --merge-branch pr-branch --merge-branch fix-branch  # Merge multiple"
            echo "  $0 --os fedora42                                          # Build on Fedora 42"
            echo "  $0 --os fedora42 --compiler gcc                             # Build on Fedora with GCC"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate compiler flag
if [ -n "$COMPILER" ]; then
    COMPILER_FLAGS=(clang gcc clang-20 clang-20-libcpp gcc-12 gcc-14)
    VALID=false
    for flag in "${COMPILER_FLAGS[@]}"; do
        if [ "$COMPILER" = "$flag" ]; then
            VALID=true
            break
        fi
    done
    if [ "$VALID" = "false" ]; then
        echo "ERROR: Unknown compiler '$COMPILER'. Allowed: ${COMPILER_FLAGS[*]}"
        exit 1
    fi
fi

# Fetch commit hash from GitHub if not specified
if [ -z "$COMMIT_HASH" ]; then
    echo "Fetching commit hash for branch/ref: $TT_METAL_BRANCH"

    # Try to fetch the commit hash using git ls-remote
    # First, try as a branch
    COMMIT_HASH=$(git ls-remote https://github.com/tenstorrent/tt-metal.git "refs/heads/$TT_METAL_BRANCH" 2>/dev/null | cut -f1)
    CHECKOUT_REF="$TT_METAL_BRANCH"
    REF_TYPE="branch"

    # If not found as branch, try as a tag
    if [ -z "$COMMIT_HASH" ]; then
        COMMIT_HASH=$(git ls-remote https://github.com/tenstorrent/tt-metal.git "refs/tags/$TT_METAL_BRANCH" 2>/dev/null | cut -f1)
        CHECKOUT_REF="$TT_METAL_BRANCH"
        REF_TYPE="tag"
    fi

    # If still not found, try with ^{} suffix for annotated tags
    if [ -z "$COMMIT_HASH" ]; then
        COMMIT_HASH=$(git ls-remote https://github.com/tenstorrent/tt-metal.git "refs/tags/$TT_METAL_BRANCH^{}" 2>/dev/null | cut -f1)
        CHECKOUT_REF="$TT_METAL_BRANCH"
        REF_TYPE="tag"
    fi

    # If still not found, assume it's already a commit hash
    if [ -z "$COMMIT_HASH" ]; then
        echo "Warning: Could not find branch or tag '$TT_METAL_BRANCH' on GitHub"
        echo "Assuming it's a commit hash or will be resolved during clone"
        COMMIT_HASH="$TT_METAL_BRANCH"
        CHECKOUT_REF="$TT_METAL_BRANCH"
        REF_TYPE="commit"
    fi
else
    echo "Using provided commit hash: $COMMIT_HASH"
    CHECKOUT_REF="$COMMIT_HASH"
    REF_TYPE="commit"
fi

# Truncate commit hash to first 10 characters for image name
COMMIT_HASH_SHORT="${COMMIT_HASH:0:10}"

echo "Commit hash (short): $COMMIT_HASH_SHORT"
echo "Checkout ref: $CHECKOUT_REF ($REF_TYPE)"

# Generate image repository name based on options
IMAGE_REPO="${USER}-tt-metal-env-${OS_LABEL}"
if [ "$BUILD_TTMETAL" = "true" ]; then
    IMAGE_REPO="${IMAGE_REPO}-built-${BUILD_TYPE,,}"
else
    IMAGE_REPO="${IMAGE_REPO}-base"
fi

# Always append commit hash to repository name
IMAGE_REPO="${IMAGE_REPO}-${COMMIT_HASH_SHORT}"

# Append merge branch info to image name (use last component of first branch)
if [ ${#MERGE_BRANCHES[@]} -gt 0 ]; then
    MERGE_LABEL="${MERGE_BRANCHES[0]##*/}"  # last path component
    MERGE_LABEL="${MERGE_LABEL##*:}"        # after : for fork syntax
    MERGE_LABEL="${MERGE_LABEL:0:20}"
    MERGE_LABEL="${MERGE_LABEL%-}"  # strip trailing dash from truncation
    IMAGE_REPO="${IMAGE_REPO}-merge-${MERGE_LABEL}"
fi

# Append compiler override to image name
if [ -n "$COMPILER" ]; then
    IMAGE_REPO="${IMAGE_REPO}-${COMPILER}"
fi

# Append tt-train compiler override to image name
if [ "$TT_TRAIN_COMPILER" != "none" ]; then
    IMAGE_REPO="${IMAGE_REPO}-tttrain-${TT_TRAIN_COMPILER}"
fi

if [ -n "$IMAGE_TAG_SUFFIX" ]; then
    IMAGE_REPO="${IMAGE_REPO}-${IMAGE_TAG_SUFFIX}"
fi

# The tag is "latest" for the fresh build
IMAGE_TAG="latest"
FULL_IMAGE_NAME="${IMAGE_REPO}:${IMAGE_TAG}"

echo "Building Docker image: $FULL_IMAGE_NAME"
echo "Configuration:"
echo "  BASE_IMAGE: $BASE_IMAGE ($OS_LABEL)"
echo "  BUILD_TTMETAL: $BUILD_TTMETAL"
echo "  BUILD_TYPE: $BUILD_TYPE"
echo "  TT_METAL_BRANCH: $TT_METAL_BRANCH"
echo "  COMMIT_HASH: $COMMIT_HASH_SHORT"
echo "  COMPILER: ${COMPILER:-default (clang-20)}"
echo "  TT_TRAIN_COMPILER: $TT_TRAIN_COMPILER"
echo "  SKIP_TT_TRAIN_STANDALONE: $SKIP_TT_TRAIN_STANDALONE"
echo "  MERGE_BRANCHES: ${MERGE_BRANCHES[*]:-none}"
echo "  SSH_KEY_PATH: $SSH_KEY_PATH"

# Check if ANY image with this repository name already exists
EXISTING_IMAGES=$(docker images "${IMAGE_REPO}" --format "{{.Repository}}:{{.Tag}}" 2>/dev/null)

if [ -n "$EXISTING_IMAGES" ]; then
    echo ""
    echo "WARNING: Images for this commit already exist!"
    echo ""
    docker images "${IMAGE_REPO}" --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedAt}}\t{{.Size}}" 2>/dev/null
    echo ""

    if [ "$FORCE_BUILD" = "false" ]; then
        echo "ERROR: Image repository already exists. Build cancelled."
        echo ""
        echo "This means you've already built an image for commit ${COMMIT_HASH_SHORT}."
        echo ""
        echo "Options:"
        echo "  1. Use the existing image:"
        echo "     ./run_tt_docker.sh --image ${IMAGE_REPO}"
        echo ""
        echo "  2. Use --force to rebuild (will REPLACE the 'latest' tag):"
        echo "     ./build_tt_docker.sh --force"
        echo ""
        echo "  3. Backup your current 'latest' first, then rebuild:"
        echo "     docker tag ${IMAGE_REPO}:latest ${IMAGE_REPO}:base-backup-$(date +%Y-%m-%d)"
        echo "     ./build_tt_docker.sh --force"
        echo ""
        echo "  4. Build a different commit/branch:"
        echo "     ./build_tt_docker.sh --branch <different-branch>"
        echo ""
        echo "  5. Remove existing images for this commit:"
        echo "     docker rmi \$(docker images ${IMAGE_REPO} -q)"
        exit 1
    else
        echo "WARNING: Continuing build due to --force flag"
        echo "The 'latest' tag will be REPLACED with the new build"
        echo ""
    fi
fi

# Check if SSH keys exist
if [ ! -d "$SSH_KEY_PATH" ] || ([ ! -f "$SSH_KEY_PATH/id_rsa" ] && [ ! -f "$SSH_KEY_PATH/id_ed25519" ]); then
    echo "Warning: SSH keys not found at $SSH_KEY_PATH"
    echo "You may need to specify the correct path with --ssh-key"
fi

# Create ccache directory if it doesn't exist
if [ ! -d "$CCACHE_HOST_DIR" ]; then
    echo "Creating ccache directory: $CCACHE_HOST_DIR"
    mkdir -p "$CCACHE_HOST_DIR"
fi

# Show current ccache size
if [ -d "$CCACHE_HOST_DIR" ]; then
    CCACHE_SIZE=$(du -sh "$CCACHE_HOST_DIR" 2>/dev/null | cut -f1)
    echo "  Current ccache size: ${CCACHE_SIZE:-empty}"
fi

# Enable BuildKit for advanced features
export DOCKER_BUILDKIT=1
export BUILDKIT_PROGRESS=plain

# Start SSH agent and add ALL available keys for build
eval $(ssh-agent -s)
for key in "$SSH_KEY_PATH"/id_*; do
    # Skip public keys and non-files
    [[ "$key" == *.pub ]] && continue
    [[ ! -f "$key" ]] && continue
    ssh-add "$key" 2>/dev/null
done

# Verify at least one key was added
if ! ssh-add -l >/dev/null 2>&1; then
    echo "ERROR: No SSH keys could be added to the agent"
    echo "Please ensure you have SSH keys in $SSH_KEY_PATH"
    exit 1
fi

# Show which keys are loaded
echo "SSH keys loaded:"
ssh-add -l

# Build the image with SSH forwarding
echo "Starting Docker build..."
DOCKER_NO_CACHE=""
if [ "$NO_CACHE" = "true" ]; then
    DOCKER_NO_CACHE="--no-cache"
fi

docker build \
    $DOCKER_NO_CACHE \
    --ssh default \
    --build-arg BASE_IMAGE=$BASE_IMAGE \
    --build-arg BUILD_TTMETAL=$BUILD_TTMETAL \
    --build-arg BUILD_TYPE=$BUILD_TYPE \
    --build-arg CHECKOUT_REF=$CHECKOUT_REF \
    --build-arg EXPECTED_COMMIT_HASH=$COMMIT_HASH \
    --build-arg REF_TYPE=$REF_TYPE \
    --build-arg TT_TRAIN_COMPILER=$TT_TRAIN_COMPILER \
    --build-arg COMPILER=$COMPILER \
    --build-arg SKIP_TT_TRAIN_STANDALONE=$SKIP_TT_TRAIN_STANDALONE \
    --build-arg "MERGE_BRANCHES=${MERGE_BRANCHES[*]}" \
    -t "${FULL_IMAGE_NAME}" \
    -f Dockerfile \
    .

BUILD_RESULT=$?

# Kill SSH agent
ssh-agent -k

if [ $BUILD_RESULT -eq 0 ]; then
    echo "Successfully built image: $FULL_IMAGE_NAME"
    echo ""
    echo "To run this image:"
    echo "  ./run_tt_docker.sh --image ${IMAGE_REPO}"
    echo ""
    echo "To backup your running container later (after making changes):"
    echo "  docker commit ${USER}-tt-metal-container ${IMAGE_REPO}:backup-$(date +%Y-%m-%d)-1"

    # Show updated ccache size if applicable
    if [ -d "$CCACHE_HOST_DIR" ]; then
        CCACHE_SIZE_AFTER=$(du -sh "$CCACHE_HOST_DIR" 2>/dev/null | cut -f1)
        echo "  Ccache directory size: ${CCACHE_SIZE_AFTER:-empty}"
    fi
else
    echo "Failed to build image"
    exit 1
fi

