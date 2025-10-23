#!/bin/bash

# Default values
IMAGE_TAG="${USER}-tt-metal-env-built-debug"  # Default to built image
CONTAINER_NAME="${USER}-tt-metal-container"
CCACHE_HOST_DIR="${HOME}/.cache/ccache-docker"
MOUNT_WORKSPACE=false
WORKSPACE_DIR="$(pwd)/workspace"
USE_CCACHE=true  # Default to true for ccache sharing
SSH_KEY_PATH="${HOME}/.ssh"
MOUNT_SSH=true

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --image)
            IMAGE_TAG="$2"
            shift 2
            ;;
        --name)
            CONTAINER_NAME="$2"
            shift 2
            ;;
        --ccache-dir)
            CCACHE_HOST_DIR="$2"
            USE_CCACHE=true
            shift 2
            ;;
        --no-ccache)
            USE_CCACHE=false
            shift
            ;;
        --mount-workspace)
            MOUNT_WORKSPACE=true
            if [ -n "$2" ] && [[ "$2" != --* ]]; then
                WORKSPACE_DIR="$2"
                shift 2
            else
                shift
            fi
            ;;
        --ssh-key)
            SSH_KEY_PATH="$2"
            shift 2
            ;;
        --no-ssh)
            MOUNT_SSH=false
            shift
            ;;
        --base)
            IMAGE_TAG="${USER}-tt-metal-env-base"
            shift
            ;;
        --built-debug)
            IMAGE_TAG="${USER}-tt-metal-env-built-debug"
            shift
            ;;
        --built-release)
            IMAGE_TAG="${USER}-tt-metal-env-built-release"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --image TAG         Docker image tag to use [default: ${USER}-tt-metal-env-built-debug]"
            echo "  --name NAME         Container name"
            echo "  --ccache-dir DIR    Host ccache directory [default: ~/.cache/ccache-docker]"
            echo "  --no-ccache         Don't mount ccache directory"
            echo "  --mount-workspace [DIR] Mount host directory as workspace"
            echo "  --ssh-key PATH      Path to SSH keys directory [default: ~/.ssh]"
            echo "  --no-ssh            Don't mount SSH keys"
            echo "  --base              Use base image (no tt-metal built)"
            echo "  --built-debug       Use pre-built debug image (default)"
            echo "  --built-release     Use pre-built release image"
            echo "  -h, --help          Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check if image exists
if ! docker image inspect "${IMAGE_TAG}" >/dev/null 2>&1; then
    echo "Error: Docker image '$IMAGE_TAG' not found!"
    echo "Available images:"
    docker images | grep "${USER}-tt-metal-env" | awk '{print "  " $1 ":" $2}'
    echo ""
    echo "Build an image first using: ./build_tt_docker.sh"
    exit 1
fi

# Check if tenstorrent module is loaded
if ! lsmod | grep -q tenstorrent; then
    echo "Warning: tenstorrent kernel module is not loaded on the host."
    echo "You may need to run: sudo modprobe tenstorrent"
fi

# Check if the device exists
if [ ! -e /dev/tenstorrent ]; then
    echo "Warning: /dev/tenstorrent device not found!"
fi

echo "Running container:"
echo "  Image: $IMAGE_TAG"
echo "  Container name: $CONTAINER_NAME"

# Prepare volume mounts
VOLUME_MOUNTS=""

# Mount ccache directory for sharing between containers
if [ "$USE_CCACHE" = "true" ]; then
    if [ ! -d "$CCACHE_HOST_DIR" ]; then
        echo "Creating ccache directory: $CCACHE_HOST_DIR"
        mkdir -p "$CCACHE_HOST_DIR"
    fi

    # Ensure proper permissions
    chmod 755 "$CCACHE_HOST_DIR"

    VOLUME_MOUNTS="$VOLUME_MOUNTS -v $CCACHE_HOST_DIR:/ccache:rw"
    CCACHE_SIZE=$(du -sh "$CCACHE_HOST_DIR" 2>/dev/null | cut -f1)
    echo "  Mounting ccache: $CCACHE_HOST_DIR -> /ccache (size: ${CCACHE_SIZE:-empty})"
fi

# Mount SSH keys if requested
if [ "$MOUNT_SSH" = "true" ] && [ -d "$SSH_KEY_PATH" ]; then
    VOLUME_MOUNTS="$VOLUME_MOUNTS -v $SSH_KEY_PATH:/host-ssh:ro"
    echo "  Mounting SSH keys: $SSH_KEY_PATH -> /host-ssh"
fi

# Mount workspace if requested
if [ "$MOUNT_WORKSPACE" = "true" ]; then
    mkdir -p "$WORKSPACE_DIR"
    VOLUME_MOUNTS="$VOLUME_MOUNTS -v $WORKSPACE_DIR:/workspace/user"
    echo "  Mounting workspace: $WORKSPACE_DIR -> /workspace/user"
fi

# Mount tt-kmd and tt-flash from host
if [ -d "/opt/tt-kmd" ]; then
    VOLUME_MOUNTS="$VOLUME_MOUNTS -v /opt/tt-kmd:/opt/tt-kmd:ro"
    echo "  Mounting tt-kmd from host"
fi

if [ -d "/opt/tt-flash" ]; then
    VOLUME_MOUNTS="$VOLUME_MOUNTS -v /opt/tt-flash:/opt/tt-flash:ro"
    echo "  Mounting tt-flash from host"
fi

# Run the container
docker run -it --rm \
    --name $CONTAINER_NAME \
    --privileged \
    --device=/dev/tenstorrent:/dev/tenstorrent \
    -v /dev:/dev \
    -v /sys:/sys \
    -v /lib/modules:/lib/modules:ro \
    -v /dev/hugepages:/dev/hugepages \
    --cap-add=ALL \
    --security-opt apparmor=unconfined \
    -e DISPLAY=$DISPLAY \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    $VOLUME_MOUNTS \
    $IMAGE_TAG

