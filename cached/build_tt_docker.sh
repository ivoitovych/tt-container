#!/bin/bash

# Parse command line arguments
BUILD_TTMETAL=true  # Default to building tt-metal
BUILD_TYPE="Debug"
IMAGE_TAG_SUFFIX=""
CCACHE_HOST_DIR="${HOME}/.cache/ccache-docker"
SSH_KEY_PATH="${HOME}/.ssh"
TT_METAL_BRANCH="main"
COMMIT_HASH=""  # Will be fetched from GitHub
FORCE_BUILD=false

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
        --force)
            FORCE_BUILD=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --no-build          Don't build tt-metal during image creation"
            echo "  --skip-ttmetal      Same as --no-build"
            echo "  --build-type TYPE   Build type (Debug/Release) [default: Debug]"
            echo "  --branch BRANCH     tt-metal branch or commit hash [default: main]"
            echo "  --commit-hash HASH  Specify commit hash directly (skips auto-fetch)"
            echo "  --tag-suffix SUFFIX Custom suffix for image tag"
            echo "  --ccache-dir DIR    Host ccache directory [default: ~/.cache/ccache-docker]"
            echo "  --ssh-key PATH      Path to SSH keys directory [default: ~/.ssh]"
            echo "  --force             Force rebuild even if image exists"
            echo "  -h, --help          Show this help message"
            echo ""
            echo "Default: Builds tt-metal in Debug mode from main branch"
            echo "Image name will include commit hash: <user>-tt-metal-env-built-<type>-<hash>:latest"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Fetch commit hash from GitHub if not specified
if [ -z "$COMMIT_HASH" ]; then
    echo "Fetching commit hash for branch/ref: $TT_METAL_BRANCH"

    # Try to fetch the commit hash using git ls-remote
    # First, try as a branch
    COMMIT_HASH=$(git ls-remote https://github.com/tenstorrent/tt-metal.git "refs/heads/$TT_METAL_BRANCH" 2>/dev/null | cut -f1)

    # If not found as branch, try as a tag
    if [ -z "$COMMIT_HASH" ]; then
        COMMIT_HASH=$(git ls-remote https://github.com/tenstorrent/tt-metal.git "refs/tags/$TT_METAL_BRANCH" 2>/dev/null | cut -f1)
    fi

    # If still not found, try with ^{} suffix for annotated tags
    if [ -z "$COMMIT_HASH" ]; then
        COMMIT_HASH=$(git ls-remote https://github.com/tenstorrent/tt-metal.git "refs/tags/$TT_METAL_BRANCH^{}" 2>/dev/null | cut -f1)
    fi

    # If still not found, assume it's already a commit hash
    if [ -z "$COMMIT_HASH" ]; then
        echo "Warning: Could not find branch or tag '$TT_METAL_BRANCH' on GitHub"
        echo "Assuming it's a commit hash or will be resolved during clone"
        COMMIT_HASH="$TT_METAL_BRANCH"
    fi
else
    echo "Using provided commit hash: $COMMIT_HASH"
fi

# Truncate commit hash to first 10 characters for image name
COMMIT_HASH_SHORT="${COMMIT_HASH:0:10}"

echo "Commit hash (short): $COMMIT_HASH_SHORT"

# Generate image repository name based on options
IMAGE_REPO="${USER}-tt-metal-env"
if [ "$BUILD_TTMETAL" = "true" ]; then
    IMAGE_REPO="${IMAGE_REPO}-built-${BUILD_TYPE,,}"
else
    IMAGE_REPO="${IMAGE_REPO}-base"
fi

# Always append commit hash to repository name
IMAGE_REPO="${IMAGE_REPO}-${COMMIT_HASH_SHORT}"

if [ -n "$IMAGE_TAG_SUFFIX" ]; then
    IMAGE_REPO="${IMAGE_REPO}-${IMAGE_TAG_SUFFIX}"
fi

# The tag is "latest" for the fresh build
IMAGE_TAG="latest"
FULL_IMAGE_NAME="${IMAGE_REPO}:${IMAGE_TAG}"

echo "Building Docker image: $FULL_IMAGE_NAME"
echo "Configuration:"
echo "  BUILD_TTMETAL: $BUILD_TTMETAL"
echo "  BUILD_TYPE: $BUILD_TYPE"
echo "  TT_METAL_BRANCH: $TT_METAL_BRANCH"
echo "  COMMIT_HASH: $COMMIT_HASH_SHORT"
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

# Start SSH agent and add keys for build
eval $(ssh-agent -s)
ssh-add "$SSH_KEY_PATH/id_rsa" 2>/dev/null || ssh-add "$SSH_KEY_PATH/id_ed25519" 2>/dev/null || true

# Build the image with SSH forwarding
echo "Starting Docker build..."
docker build \
    --ssh default \
    --build-arg BUILD_TTMETAL=$BUILD_TTMETAL \
    --build-arg BUILD_TYPE=$BUILD_TYPE \
    --build-arg TT_METAL_BRANCH=$TT_METAL_BRANCH \
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

