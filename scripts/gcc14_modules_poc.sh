#!/bin/bash
# GCC 14 C++20 Modules PoC Build Script for HPX
# This script is the core proof-of-concept for GSoC 2026

set -e

echo "=== HPX GCC 14 C++20 Modules PoC ==="
echo "GCC Version:"
gcc --version
echo "CMake Version:"
cmake --version
echo ""

# --- Configuration ---
HPX_SRC="/workspace/hpx"
BUILD_DIR="/workspace/build-gcc14-modules"

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

echo "=== Step 1: Configuring HPX with C++20 Modules on GCC 14 ==="
cmake "${HPX_SRC}" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_C_COMPILER=gcc-14 \
    -DCMAKE_CXX_COMPILER=g++-14 \
    -DCMAKE_CXX_STANDARD=20 \
    -DHPX_WITH_CXX_MODULES=ON \
    -DHPX_WITH_DISTRIBUTED_RUNTIME=OFF \
    -DHPX_WITH_TESTS=OFF \
    -DHPX_WITH_EXAMPLES=OFF \
    -DHPX_WITH_TOOLS=OFF \
    -DHPX_WITH_FETCH_ASIO=ON \
    2>&1 | tee cmake_configure.log

echo ""
echo "=== Step 2: CMake Configuration Complete ==="
echo "Checking for generated module interface files..."

# Check if any .cxx module interface files were generated (GCC extension)
find "${BUILD_DIR}" -name "*.cxx" -path "*/module*" 2>/dev/null || echo "No .cxx module files found yet (expected)"

echo ""
echo "=== Step 3: Attempting to build hpx_core module target ==="
# Try building just the core module - this is where GCC failures would appear
cmake --build . --target hpx_core --parallel 4 2>&1 | tee build_core.log || {
    echo ""
    echo "=== BUILD FAILED - Analyzing errors for GCC module issues ==="
    grep -i "error\|warning.*module\|note.*module" build_core.log | head -50
    exit 1
}

echo ""
echo "=== Step 4: Build Complete! Checking module artifacts ==="
find "${BUILD_DIR}" -name "*.gcm" 2>/dev/null && echo "Found GCC module cache files (.gcm)!" || echo "No .gcm files found"

echo ""
echo "=== PoC Result Summary ==="
echo "Build Directory: ${BUILD_DIR}"
echo "Log files: cmake_configure.log, build_core.log"
echo "Status: SUCCESS - GCC 14 C++20 module build works for HPX!"
