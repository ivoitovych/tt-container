#!/bin/bash
# Reproduction script for tt-train clang-20 build failure
#
# Bug: tt-train fails to build with clang-20 due to deprecated
#      std::get_temporary_buffer in flatbuffers dependency
#
# tt-metal branch: ivoitovych/bug-tt-train-clang20
# This branch:
#   - Modifies install_dependencies.sh to only install clang-20
#   - Updates tt-train to use clang-20 instead of clang-17
#
# Expected result: Build fails during tt-train compilation with errors like:
#   error: 'get_temporary_buffer<...>' is deprecated [-Werror,-Wdeprecated-declarations]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== tt-train clang-20 Build Failure Reproduction ==="
echo ""
echo "This will build tt-metal with branch: ivoitovych/bug-tt-train-clang20"
echo "which configures tt-train to use clang-20 instead of clang-17."
echo ""
echo "The build is expected to FAIL during tt-train compilation."
echo ""

# Build with the bug reproduction branch
"${SCRIPT_DIR}/build_tt_docker.sh" \
    --branch ivoitovych/bug-tt-train-clang20 \
    --tag-suffix "-clang20-repro" \
    "$@"
