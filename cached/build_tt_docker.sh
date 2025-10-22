#!/bin/bash

# Parse command line arguments
BUILD_TTMETAL=true  # Default to building tt-metal
BUILD_TYPE="Debug"
IMAGE_TAG_SUFFIX=""
CCACHE_HOST_DIR="${HOME}/.cache/ccache-docker"
SSH_KEY_PATH="${HOME}/.ssh"
TT_METAL_BRANCH="main"

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
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --no-build          Don't build tt-metal during image creation"
            echo "  --skip-ttmetal      Same as --no-build"
            echo "  --build-type TYPE   Build type (Debug/Release) [default: Debug]"
            echo "  --branch BRANCH     tt-metal branch or commit hash [default: main]"
            echo "  --tag-suffix SUFFIX Custom suffix for image tag"
            echo "  --ccache-dir DIR    Host ccache directory [default: ~/.cache/ccache-docker]"
            echo "  --ssh-key PATH      Path to SSH keys directory [default: ~/.ssh]"
            echo "  -h, --help          Show this help message"
            echo ""
            echo "Default: Builds tt-metal in Debug mode"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Generate image tag based on options
IMAGE_TAG="${USER}-tt-metal-env"
if [ "$BUILD_TTMETAL" = "true" ]; then
    IMAGE_TAG="${IMAGE_TAG}-built-${BUILD_TYPE,,}"
else
    IMAGE_TAG="${IMAGE_TAG}-base"
fi
if [ "$TT_METAL_BRANCH" != "main" ]; then
    # Sanitize branch name for docker tag (replace / with -)
    BRANCH_TAG=$(echo "$TT_METAL_BRANCH" | sed 's/[^a-zA-Z0-9._-]/-/g' | cut -c1-20)
    IMAGE_TAG="${IMAGE_TAG}-${BRANCH_TAG}"
fi
if [ -n "$IMAGE_TAG_SUFFIX" ]; then
    IMAGE_TAG="${IMAGE_TAG}-${IMAGE_TAG_SUFFIX}"
fi

echo "Building Docker image: $IMAGE_TAG"
echo "Configuration:"
echo "  BUILD_TTMETAL: $BUILD_TTMETAL"
echo "  BUILD_TYPE: $BUILD_TYPE"
echo "  TT_METAL_BRANCH: $TT_METAL_BRANCH"
echo "  SSH_KEY_PATH: $SSH_KEY_PATH"

# Check if SSH keys exist
if [ ! -d "$SSH_KEY_PATH" ] || [ ! -f "$SSH_KEY_PATH/id_rsa" ]; then
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
    -t $IMAGE_TAG \
    -f Dockerfile \
    .

BUILD_RESULT=$?

# Kill SSH agent
ssh-agent -k

if [ $BUILD_RESULT -eq 0 ]; then
    echo "Successfully built image: $IMAGE_TAG"

    # Show updated ccache size if applicable
    if [ -d "$CCACHE_HOST_DIR" ]; then
        CCACHE_SIZE_AFTER=$(du -sh "$CCACHE_HOST_DIR" 2>/dev/null | cut -f1)
        echo "  Ccache directory size: ${CCACHE_SIZE_AFTER:-empty}"
    fi
else
    echo "Failed to build image"
    exit 1
fi

