#!/bin/bash

# Check if tenstorrent module is loaded
if ! lsmod | grep -q tenstorrent; then
    echo "Warning: tenstorrent kernel module is not loaded on the host."
    echo "You may need to run: sudo modprobe tenstorrent"
fi

# Check if the device exists
if [ ! -e /dev/tenstorrent ]; then
    echo "Warning: /dev/tenstorrent device not found!"
    echo "Make sure the Tenstorrent device is properly installed."
fi

# Run the container with device access
docker run -it --rm \
    --name tt-metal-container \
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
    -v $(pwd)/workspace:/workspace/user \
    tt-metal-env

