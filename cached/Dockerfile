# syntax=docker/dockerfile:1.4
# Multi-platform tt-metal container build.
# Supported platforms:
#   Main:         ubuntu:22.04, ubuntu:24.04, fedora:40
#   Experimental: debian:12, rockylinux:9, almalinux:9, centos:stream9
ARG BASE_IMAGE=ubuntu:22.04
FROM ${BASE_IMAGE}

# Build arguments
ARG BUILD_TTMETAL=true
ARG BUILD_TYPE=Debug
ARG CHECKOUT_REF=main
ARG EXPECTED_COMMIT_HASH=unknown
ARG REF_TYPE=branch
# tt-train compiler override: "none" (inherit from CMakeCache), "clang-17", "gcc-12", etc.
ARG TT_TRAIN_COMPILER=none
# Space-separated list of branches to merge after checkout (empty = none)
ARG MERGE_BRANCHES=""
# Skip standalone tt-train builds (pip install -e and standalone cmake).
# When true, tt-train is only built via build_metal.sh --build-all (integrated build).
# Python access relies on .pth files created by create_venv.sh.
ARG SKIP_TT_TRAIN_STANDALONE=false
# Compiler selection: passed to install_dependencies.sh and build_metal.sh
# Values: "" (default clang-20), clang, gcc, clang-20, clang-20-libcpp, gcc-12, gcc-14
ARG COMPILER=

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV TT_METAL_HOME=/workspace/tt-metal
ENV TT_METAL_RUNTIME_ROOT=$TT_METAL_HOME
ENV PYTHONPATH=$TT_METAL_HOME

# Bootstrap packages — minimal set not provided by install_dependencies.sh.
# Required:  sudo, wget, ca-certificates, git, git-lfs (needed before install_dependencies.sh)
# Optional:  curl (redundant but used during repo setup), openssh-client (SSH clone),
#            ccache (build acceleration), kmod/pciutils (runtime device interaction)
# Detects package manager (apt vs dnf vs yum) and installs accordingly.
RUN if command -v apt-get >/dev/null 2>&1; then \
        apt-get update && apt-get install -y --no-install-recommends \
            sudo wget curl ca-certificates \
            git git-lfs openssh-client \
            ccache kmod pciutils \
        && rm -rf /var/lib/apt/lists/*; \
    elif command -v dnf >/dev/null 2>&1; then \
        dnf install -y \
            sudo wget curl ca-certificates \
            git git-lfs openssh-clients \
            ccache kmod pciutils \
        && dnf clean all; \
    elif command -v yum >/dev/null 2>&1; then \
        yum install -y epel-release && \
        yum install -y \
            sudo wget curl ca-certificates \
            git git-lfs openssh-clients \
            ccache kmod pciutils \
        && yum clean all; \
    else \
        echo "ERROR: No supported package manager found (apt, dnf, yum)" && exit 1; \
    fi

# Configure wget for retries on network failures
RUN echo "tries = 5" >> /etc/wgetrc && \
    echo "waitretry = 10" >> /etc/wgetrc && \
    echo "retry_connrefused = on" >> /etc/wgetrc

# Configure git and git-lfs
RUN git config --global user.email "docker@tt-metal.local" && \
    git config --global user.name "Docker User" && \
    git lfs install

# Setup SSH for GitHub (will use host's SSH keys when mounted)
RUN mkdir -p /root/.ssh && \
    printf "Host github.com\n\tStrictHostKeyChecking no\n" > /root/.ssh/config && \
    chmod 600 /root/.ssh/config

# Configure .bashrc for environment variables and history
# Remove existing HISTSIZE/HISTFILESIZE (some base images set these)
RUN echo "export TT_METAL_HOME=$TT_METAL_HOME" >> /root/.bashrc && \
    echo 'export TT_METAL_RUNTIME_ROOT=$TT_METAL_HOME' >> /root/.bashrc && \
    echo 'export PYTHONPATH=$TT_METAL_HOME' >> /root/.bashrc && \
    sed -i '/^HISTSIZE=/d; /^HISTFILESIZE=/d' /root/.bashrc && \
    echo 'HISTSIZE=-1' >> /root/.bashrc && \
    echo 'HISTFILESIZE=-1' >> /root/.bashrc

# Pre-populate bash history with useful commands
RUN echo "git log --pretty=tformat:\"%C(yellow)%h%C(reset) - %C(green)%ad%C(reset) - %C(blue)%an%C(reset) - %C(white)%s%C(reset) %C(red)%d%C(reset)\" --date=format:'%Y-%m-%d %H:%M' --graph -30" >> /root/.bash_history

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
WORKDIR $TT_METAL_HOME
RUN --mount=type=ssh \
    set -e && \
    git fetch --all --tags && \
    echo "Checking out: ${CHECKOUT_REF} (${REF_TYPE})" && \
    git checkout ${CHECKOUT_REF} && \
    ACTUAL_HASH=$(git rev-parse HEAD) && \
    echo "Checked out commit: ${ACTUAL_HASH}" && \
    echo "Expected commit:    ${EXPECTED_COMMIT_HASH}" && \
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
            exit 1 ;; \
    esac && \
    git submodule sync --recursive && \
    git submodule update --init --recursive && \
    git lfs pull && \
    git submodule foreach --recursive 'git lfs pull'

# Merge additional branches if specified
# Supports both origin branches and fork URLs (user/repo:branch)
RUN --mount=type=ssh \
    if [ -n "${MERGE_BRANCHES}" ]; then \
        for BRANCH in ${MERGE_BRANCHES}; do \
            echo "=== Merging branch: ${BRANCH} ===" && \
            if echo "${BRANCH}" | grep -q ':'; then \
                FORK_REPO=$(echo "${BRANCH}" | cut -d: -f1) && \
                FORK_BRANCH=$(echo "${BRANCH}" | cut -d: -f2) && \
                echo "Fetching from fork: git@github.com:${FORK_REPO}.git branch ${FORK_BRANCH}" && \
                git fetch "git@github.com:${FORK_REPO}.git" "${FORK_BRANCH}:merge-${FORK_BRANCH}" && \
                git merge "merge-${FORK_BRANCH}" -m "Merge ${BRANCH} for verification" || exit 1; \
            else \
                echo "Merging origin branch: ${BRANCH}" && \
                git fetch origin "${BRANCH}" && \
                git merge "FETCH_HEAD" -m "Merge ${BRANCH} for verification" || exit 1; \
            fi && \
            echo "=== Merge of ${BRANCH} complete ===" ; \
        done && \
        git submodule sync --recursive && \
        git submodule update --init --recursive; \
    else \
        echo "No additional branches to merge"; \
    fi

# Let install_dependencies.sh handle everything: cmake, clang, build tools, libraries
RUN ./install_dependencies.sh ${COMPILER:+--compiler "$COMPILER"}

# Install override compiler for tt-train if requested
# Accepts: "none" (default), "clang-N" (installs clang-N), "gcc-N" (checks gcc-N exists)
# tt-metal always builds with clang-20 from install_dependencies.sh
RUN if [ "$TT_TRAIN_COMPILER" != "none" ]; then \
        echo "=== tt-train compiler override: $TT_TRAIN_COMPILER ===" && \
        case "$TT_TRAIN_COMPILER" in \
            clang-*) \
                echo "Installing $TT_TRAIN_COMPILER..." && \
                if command -v apt-get >/dev/null 2>&1; then \
                    apt-get update && apt-get install -y "$TT_TRAIN_COMPILER" && rm -rf /var/lib/apt/lists/*; \
                elif command -v dnf >/dev/null 2>&1; then \
                    dnf install -y "$TT_TRAIN_COMPILER"; \
                else \
                    echo "ERROR: No supported package manager for installing $TT_TRAIN_COMPILER" && exit 1; \
                fi && \
                "$TT_TRAIN_COMPILER" --version ;; \
            gcc-*) \
                GCCVER="$TT_TRAIN_COMPILER" && \
                GXXVER="g++-${GCCVER#gcc-}" && \
                echo "Verifying $GCCVER / $GXXVER..." && \
                "$GCCVER" --version && "$GXXVER" --version ;; \
            *) \
                echo "ERROR: Unknown compiler format: $TT_TRAIN_COMPILER (expected clang-N or gcc-N)" && exit 1 ;; \
        esac; \
    fi

# Setup ccache configuration
RUN mkdir -p /etc/ccache && \
    echo "cache_dir = /ccache" > /etc/ccache/ccache.conf && \
    echo "max_size = 10G" >> /etc/ccache/ccache.conf

# Build tt-metal with cache mount
# Note: build runs BEFORE create_venv.sh — build_metal.sh uses system Python
# for CMake discovery and does not need the venv. This ordering ensures that
# create_venv.sh finds the build output and creates _ttml.pth for the C++ extension.
WORKDIR $TT_METAL_HOME
RUN --mount=type=cache,target=/ccache,uid=1000,gid=1000,sharing=shared \
    if [ "$BUILD_TTMETAL" = "true" ]; then \
        echo "Building tt-metal with build type: ${BUILD_TYPE}" && \
        export CCACHE_DIR=/ccache && \
        export PATH=/usr/lib/ccache:$PATH && \
        ccache -M 10G && \
        echo "Initial ccache statistics:" && \
        ccache -z && \
        ccache -s && \
        BUILD_TYPE_LOWER=$(echo ${BUILD_TYPE} | tr '[:upper:]' '[:lower:]') && \
        ./build_metal.sh --${BUILD_TYPE_LOWER} --build-all --enable-ccache ${COMPILER:+--compiler "$COMPILER"} && \
        echo "Final ccache statistics:" && \
        ccache -s; \
    else \
        echo "Skipping tt-metal build (BUILD_TTMETAL=false)"; \
    fi

# Create Python virtual environment for tt-metal
# Runs AFTER build so that create_venv.sh finds build/tt-train/sources/ttml/
# and creates _ttml.pth pointing to the built C++ extension.
RUN ./create_venv.sh

# Install ttml Python module (editable for development)
# Skipped when SKIP_TT_TRAIN_STANDALONE=true (relies on .pth files from create_venv.sh instead)
RUN if [ "$BUILD_TTMETAL" = "true" ] && [ "$SKIP_TT_TRAIN_STANDALONE" != "true" ]; then \
        echo "Installing ttml Python module via pip..." && \
        . $TT_METAL_HOME/python_env/bin/activate && \
        uv pip install -e $TT_METAL_HOME/tt-train && \
        deactivate; \
    elif [ "$BUILD_TTMETAL" = "true" ]; then \
        echo "Skipping standalone pip install (SKIP_TT_TRAIN_STANDALONE=true)" && \
        echo "ttml Python access via .pth files from create_venv.sh"; \
    else \
        echo "Skipping ttml installation (BUILD_TTMETAL=false)"; \
    fi

# Build tt-train C++ components standalone (with cache mount)
# When TT_TRAIN_COMPILER is set, override the compiler and disable inheritance
# Skipped when SKIP_TT_TRAIN_STANDALONE=true (tt-train already built via build_metal.sh --build-all)
RUN --mount=type=cache,target=/ccache,uid=1000,gid=1000,sharing=shared \
    if [ "$BUILD_TTMETAL" = "true" ] && [ "$SKIP_TT_TRAIN_STANDALONE" != "true" ]; then \
        echo "Building tt-train with build type: ${BUILD_TYPE}" && \
        export CCACHE_DIR=/ccache && \
        export PATH=/usr/lib/ccache:$PATH && \
        cd $TT_METAL_HOME/tt-train && \
        rm -rf build/ && \
        CMAKE_EXTRA_ARGS="" && \
        if [ "$TT_TRAIN_COMPILER" != "none" ]; then \
            case "$TT_TRAIN_COMPILER" in \
                clang-*) \
                    CXX_NAME="clang++-${TT_TRAIN_COMPILER#clang-}" ;; \
                gcc-*) \
                    CXX_NAME="g++-${TT_TRAIN_COMPILER#gcc-}" ;; \
            esac && \
            CMAKE_EXTRA_ARGS="-DTT_TRAIN_INHERIT_COMPILER=OFF -DCMAKE_C_COMPILER=$TT_TRAIN_COMPILER -DCMAKE_CXX_COMPILER=$CXX_NAME" && \
            echo "=== OVERRIDE: building tt-train with $TT_TRAIN_COMPILER / $CXX_NAME ==="; \
        else \
            echo "=== DEFAULT: tt-train inherits compiler from tt-metal CMakeCache.txt ==="; \
        fi && \
        cmake -DCMAKE_BUILD_TYPE=${BUILD_TYPE} \
              -DCMAKE_C_COMPILER_LAUNCHER=ccache \
              -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
              $CMAKE_EXTRA_ARGS \
              -B build -GNinja && \
        cmake --build build --config ${BUILD_TYPE} --clean-first && \
        echo "tt-train standalone build completed"; \
    elif [ "$BUILD_TTMETAL" = "true" ]; then \
        echo "Skipping standalone tt-train build (SKIP_TT_TRAIN_STANDALONE=true)" && \
        echo "tt-train C++ components built via build_metal.sh --build-all"; \
    else \
        echo "Skipping tt-train build (BUILD_TTMETAL=false)"; \
    fi

# Install tt-smi
WORKDIR /workspace/tt-smi
RUN python3 -m venv .venv && \
    . .venv/bin/activate && \
    pip3 install --upgrade pip && \
    pip install . && \
    deactivate

# Set working directory back to tt-metal
WORKDIR $TT_METAL_HOME

# Create entrypoint script
RUN echo '#!/bin/bash\n\
source $TT_METAL_HOME/python_env/bin/activate\n\
export CCACHE_DIR=/ccache\n\
export PATH=/usr/lib/ccache:$PATH\n\
if [ -d "/ccache" ] && [ -w "/ccache" ]; then\n\
    echo "Ccache directory mounted and writable"\n\
    ccache -M 10G 2>/dev/null || true\n\
else\n\
    echo "Warning: Ccache directory not mounted or not writable"\n\
fi\n\
if [ -d "/host-ssh" ]; then\n\
    cp -r /host-ssh/* /root/.ssh/ 2>/dev/null || true\n\
    chmod 600 /root/.ssh/* 2>/dev/null || true\n\
fi\n\
exec "$@"' > /entrypoint.sh && \
    chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/bash"]
