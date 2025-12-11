# syntax=docker/dockerfile:1.4
# Use Ubuntu 22.04 as base (matching your environment)
FROM ubuntu:22.04

# Build arguments
ARG BUILD_TTMETAL=true
ARG BUILD_TYPE=Debug
ARG CHECKOUT_REF=main
ARG EXPECTED_COMMIT_HASH=unknown
ARG REF_TYPE=branch

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV TT_METAL_HOME=/workspace/tt-metal
ENV PYTHONPATH=/workspace/tt-metal
ENV ARCH_NAME=wormhole_b0
ENV PATH=/opt/cmake/bin:$PATH

RUN apt-get update && apt-get install -y \
    # Basic tools
    sudo \
    wget \
    curl \
    git \
    git-lfs \
    vim \
    nano \
    openssh-client \
    # Build tools
    build-essential \
    dkms \
    ccache \
    ninja-build \
    pkg-config \
    clang \
    llvm \
    # Python
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    python3-numpy \
    # Libraries
    libstdc++-12-dev \
    libmpfr-dev \
    libgmp-dev \
    libmpc-dev \
    libnuma-dev \
    libhwloc-dev \
    libtbb-dev \
    libcapstone-dev \
    # MPI support
    libopenmpi-dev \
    openmpi-bin \
    # Additional tools
    cargo \
    pandoc \
    graphviz \
    doxygen \
    texlive-latex-base \
    # System tools
    kmod \
    pciutils \
    && rm -rf /var/lib/apt/lists/*

# Configure wget for retries on network failures
RUN echo "tries = 5" >> /etc/wgetrc && \
    echo "waitretry = 10" >> /etc/wgetrc && \
    echo "retry_connrefused = on" >> /etc/wgetrc

# Install CMake 3.30.9 from source (required for tt-train)
RUN wget https://github.com/Kitware/CMake/releases/download/v3.30.9/cmake-3.30.9-linux-x86_64.tar.gz && \
    tar -xzf cmake-3.30.9-linux-x86_64.tar.gz && \
    mv cmake-3.30.9-linux-x86_64 /opt/cmake && \
    rm cmake-3.30.9-linux-x86_64.tar.gz

# Configure git and git-lfs
RUN git config --global user.email "docker@tt-metal.local" && \
    git config --global user.name "Docker User" && \
    git lfs install

# Setup SSH for GitHub (will use host's SSH keys when mounted)
RUN mkdir -p /root/.ssh && \
    echo "Host github.com\n\tStrictHostKeyChecking no\n" > /root/.ssh/config && \
    chmod 600 /root/.ssh/config

# Create workspace directory
WORKDIR /workspace

# Cache buster: Include expected commit hash to invalidate cache when it changes
RUN echo "Expected commit: ${EXPECTED_COMMIT_HASH}" > /workspace/.expected_commit

# Clone repositories using SSH
RUN --mount=type=ssh \
    git clone git@github.com:tenstorrent/tt-system-tools.git && \
    git clone git@github.com:tenstorrent/tt-smi.git && \
    git clone git@github.com:tenstorrent/tt-metal.git

# Checkout specific branch/commit for tt-metal and verify
WORKDIR /workspace/tt-metal
RUN --mount=type=ssh \
    set -e && \
    git fetch --all --tags && \
    echo "Checking out: ${CHECKOUT_REF} (${REF_TYPE})" && \
    git checkout ${CHECKOUT_REF} && \
    ACTUAL_HASH=$(git rev-parse HEAD) && \
    echo "Checked out commit: ${ACTUAL_HASH}" && \
    echo "Expected commit:    ${EXPECTED_COMMIT_HASH}" && \
    # Handle short hashes - check if actual hash starts with expected hash \
    case "${ACTUAL_HASH}" in \
        "${EXPECTED_COMMIT_HASH}"*) \
            echo "Commit hash verified successfully!" ;; \
        *) \
            echo "" && \
            echo "ERROR: Commit hash mismatch!" && \
            echo "The ${REF_TYPE} '${CHECKOUT_REF}' has moved during the build." && \
            echo "Expected: ${EXPECTED_COMMIT_HASH}" && \
            echo "Got:      ${ACTUAL_HASH}" && \
            echo "" && \
            echo "This can happen if:" && \
            echo "  - New commits were pushed to ${CHECKOUT_REF} during build" && \
            echo "  - Network delay between hash fetch and checkout" && \
            echo "" && \
            echo "Solution: Run the build script again to use the new commit hash." && \
            echo "" && \
            exit 1 ;; \
    esac && \
    git submodule sync --recursive && \
    git submodule update --init --recursive && \
    git lfs pull && \
    git submodule foreach --recursive 'git lfs pull'

# Install tt-metal dependencies
RUN ./install_dependencies.sh || true

# Create Python virtual environment for tt-metal
RUN ./create_venv.sh

# Setup ccache configuration
RUN mkdir -p /etc/ccache && \
    echo "cache_dir = /ccache" > /etc/ccache/ccache.conf && \
    echo "max_size = 10G" >> /etc/ccache/ccache.conf

# Build tt-metal with cache mount
WORKDIR /workspace/tt-metal
RUN --mount=type=cache,target=/ccache,uid=1000,gid=1000,sharing=shared \
    if [ "$BUILD_TTMETAL" = "true" ]; then \
        echo "Building tt-metal with build type: ${BUILD_TYPE}" && \
        export CCACHE_DIR=/ccache && \
        export PATH=/usr/lib/ccache:$PATH && \
        # Configure ccache
        ccache -M 10G && \
        echo "Initial ccache statistics:" && \
        ccache -z && \
        ccache -s && \
        # Build tt-metal
        . python_env/bin/activate && \
        BUILD_TYPE_LOWER=$(echo ${BUILD_TYPE} | tr '[:upper:]' '[:lower:]') && \
        ./build_metal.sh --${BUILD_TYPE_LOWER} --build-all --enable-ccache && \
        # Show ccache results
        echo "Final ccache statistics:" && \
        ccache -s && \
        deactivate; \
    else \
        echo "Skipping tt-metal build (BUILD_TTMETAL=false)"; \
    fi

# Install tt-smi
WORKDIR /workspace/tt-smi
RUN python3 -m venv .venv && \
    . .venv/bin/activate && \
    pip3 install --upgrade pip && \
    pip install . && \
    deactivate

# Set working directory back to tt-metal
WORKDIR /workspace/tt-metal

# Create entrypoint script
RUN echo '#!/bin/bash\n\
source /workspace/tt-metal/python_env/bin/activate\n\
export CCACHE_DIR=/ccache\n\
export PATH=/usr/lib/ccache:$PATH\n\
# Initialize ccache if directory is mounted\n\
if [ -d "/ccache" ] && [ -w "/ccache" ]; then\n\
    echo "Ccache directory mounted and writable"\n\
    ccache -M 10G 2>/dev/null || true\n\
else\n\
    echo "Warning: Ccache directory not mounted or not writable"\n\
fi\n\
# Mount host SSH keys if provided\n\
if [ -d "/host-ssh" ]; then\n\
    cp -r /host-ssh/* /root/.ssh/ 2>/dev/null || true\n\
    chmod 600 /root/.ssh/* 2>/dev/null || true\n\
fi\n\
exec "$@"' > /entrypoint.sh && \
    chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/bash"]

