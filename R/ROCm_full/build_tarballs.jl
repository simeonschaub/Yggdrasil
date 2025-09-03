# Note that this script can accept some limited command-line arguments, run
# `julia build_tarballs.jl --help` to see a usage message.
using BinaryBuilder, Pkg

name = "ROCm_full"
version = v"6.4.3"

# Collection of sources required to complete build
sources = [
    GitSource(
        "https://github.com/ROCm/TheRock",
        "90299bcdb49d7a7788ee74e666c5e62c487192eb",
    )
]

# Bash recipe for building across all platforms
script = raw"""
cd $WORKSPACE/srcdir/TheRock

apk del cmake python2
apk upgrade python3 --latest --update-cache --available --repository=http://dl-cdn.alpinelinux.org/alpine/edge/main || true

python3 -m venv .venv && source .venv/bin/activate
SOURCE_DATE_EPOCH=315532800 pip install -r requirements.txt

python ./build_tools/fetch_sources.py

cmake -B build -GNinja . \
    -DCMAKE_INSTALL_PREFIX=${prefix} -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TARGET_TOOLCHAIN} -DCMAKE_BUILD_TYPE=Release \
    -DTHEROCK_AMDGPU_FAMILIES="gfx101X-all;gfx103X-all;gfx110X-all;gfx1150;gfx1151;gfx1200" \
    -DTHEROCK_AMDGPU_DIST_BUNDLE_NAME="yggdrasil-rocm-targets" \
    -DTHEROCK_ENABLE_ROCPROF_TRACE_DECODER_BINARY=OFF
cmake --build build --parallel ${nproc}
cmake --install build
"""

# These are the platforms we will build for by default, unless further
# platforms are passed in on the command line
platforms = [
    Platform("x86_64", "linux"; libc="glibc", cxxstring_abi="cxx11"),
]

# The products that we will ensure are always built
products = Product[
]

# Dependencies that must be installed before this package can be built
dependencies = [
    HostBuildDependency(PackageSpec(; name = "CMake_jll", version = v"3.31.5")),
]

# Build the tarballs, and possibly a `build.jl` as well.
build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies; julia_compat="1.6", preferred_gcc_version=v"14")
