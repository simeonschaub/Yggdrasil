# Note that this script can accept some limited command-line arguments, run
# `julia build_tarballs.jl --help` to see a usage message.
using BinaryBuilder, Pkg

name = "AMDGPU_LLVM_Backend"
version = v"23.0.0"

# Collection of sources required to build AMDGPU_LLVM_Backend.
# LLVM 22 ships a single monorepo source archive (`llvm-project-X.Y.Z.src.tar.xz`).
sources = [
    GitSource("https://github.com/ROCm/llvm-project",
              "46fcb339fb61119b337f973c7ca9e710a319fdd0")
]

# Bash recipe for building across all platforms
script = raw"""
cd llvm-project/llvm
LLVM_SRCDIR=$(pwd)

install_license LICENSE.TXT

# The very first thing we need to do is to build llvm-tblgen for x86_64-linux-muslc
# This is because LLVM's cross-compile setup is kind of borked, so we just
# build the tools natively ourselves, directly.  :/

# Build llvm-tblgen and llvm-config, as well as a native clang so we can
# compile the device libraries
mkdir ${WORKSPACE}/bootstrap
pushd ${WORKSPACE}/bootstrap
CMAKE_FLAGS=()
# The device libraries only need clang to emit amdgcn bitcode, and
# llvm-tblgen/llvm-config don't need a backend at all, so skip the host target
CMAKE_FLAGS+=(-DLLVM_TARGETS_TO_BUILD:STRING=AMDGPU)
CMAKE_FLAGS+=(-DLLVM_HOST_TRIPLE=${MACHTYPE})
CMAKE_FLAGS+=(-DCMAKE_BUILD_TYPE=Release)
CMAKE_FLAGS+=(-DLLVM_ENABLE_PROJECTS='clang')
# Slim down the clang build: no static analyzer libs, no optional deps
CMAKE_FLAGS+=(-DCLANG_ENABLE_STATIC_ANALYZER=OFF)
CMAKE_FLAGS+=(-DLLVM_INCLUDE_TESTS=OFF)
CMAKE_FLAGS+=(-DLLVM_INCLUDE_EXAMPLES=OFF)
CMAKE_FLAGS+=(-DLLVM_INCLUDE_BENCHMARKS=OFF)
CMAKE_FLAGS+=(-DLLVM_INCLUDE_DOCS=OFF)
CMAKE_FLAGS+=(-DLLVM_ENABLE_ZLIB=OFF)
CMAKE_FLAGS+=(-DLLVM_ENABLE_ZSTD=OFF)
CMAKE_FLAGS+=(-DLLVM_ENABLE_LIBXML2=OFF)
CMAKE_FLAGS+=(-DCMAKE_CROSSCOMPILING=False)
CMAKE_FLAGS+=(-DCMAKE_TOOLCHAIN_FILE=${CMAKE_HOST_TOOLCHAIN})
cmake -GNinja ${LLVM_SRCDIR} ${CMAKE_FLAGS[@]}
ninja -j${nproc} llvm-tblgen llvm-config clang llvm-link opt
popd

# Build the device libraries with the native bootstrap clang and install the
# (target-independent) bitcode into $prefix
mkdir ${WORKSPACE}/device-libs
pushd ${WORKSPACE}/device-libs
CMAKE_FLAGS=()
CMAKE_FLAGS+=(-DCMAKE_BUILD_TYPE=Release)
CMAKE_FLAGS+=(-DCMAKE_INSTALL_PREFIX=${prefix})
CMAKE_FLAGS+=(-DCMAKE_PREFIX_PATH=${WORKSPACE}/bootstrap)
CMAKE_FLAGS+=(-DCMAKE_CROSSCOMPILING=False)
CMAKE_FLAGS+=(-DCMAKE_TOOLCHAIN_FILE=${CMAKE_HOST_TOOLCHAIN})
cmake -GNinja ${LLVM_SRCDIR}/../amd/device-libs ${CMAKE_FLAGS[@]}
ninja -j${nproc} install
popd

# Let's do the actual build within the `build` subdirectory
mkdir ${WORKSPACE}/build && cd ${WORKSPACE}/build
CMAKE_FLAGS=()

# Tell LLVM where our pre-built tblgen tools are
CMAKE_FLAGS+=(-DLLVM_TABLEGEN=${WORKSPACE}/bootstrap/bin/llvm-tblgen)
CMAKE_FLAGS+=(-DLLVM_CONFIG_PATH=${WORKSPACE}/bootstrap/bin/llvm-config)

# Tell CMake to enable lld in the target build
CMAKE_FLAGS+=(-DLLVM_ENABLE_PROJECTS=lld)

# Install things into $prefix
CMAKE_FLAGS+=(-DCMAKE_INSTALL_PREFIX=${prefix})

# Explicitly use our cmake toolchain file and tell CMake we're cross-compiling
CMAKE_FLAGS+=(-DCMAKE_TOOLCHAIN_FILE=${CMAKE_TARGET_TOOLCHAIN})
CMAKE_FLAGS+=(-DCMAKE_CROSSCOMPILING:BOOL=ON)

# Release build for best performance
CMAKE_FLAGS+=(-DCMAKE_BUILD_TYPE=Release)

# Only build the AMDGPU back-end
CMAKE_FLAGS+=(-DLLVM_TARGETS_TO_BUILD=AMDGPU)

# Turn on ZLIB
CMAKE_FLAGS+=(-DLLVM_ENABLE_ZLIB=ON)
# Turn off XML2 and ZSTD to avoid unnecessary dependencies
CMAKE_FLAGS+=(-DLLVM_ENABLE_ZSTD=OFF)
CMAKE_FLAGS+=(-DLLVM_ENABLE_LIBXML2=OFF)

# Disable useless things like docs, terminfo, etc....
CMAKE_FLAGS+=(-DLLVM_INCLUDE_DOCS=Off)
CMAKE_FLAGS+=(-DLLVM_ENABLE_TERMINFO=Off)
CMAKE_FLAGS+=(-DHAVE_HISTEDIT_H=Off)
CMAKE_FLAGS+=(-DHAVE_LIBEDIT=Off)

cmake -GNinja ${LLVM_SRCDIR} ${CMAKE_FLAGS[@]}
ninja -j${nproc} tools/llc/install
ninja -j${nproc} tools/lld/install
"""

# Only build for the host platforms where AMDGPU itself runs.
platforms = [
    Platform("x86_64",  "linux";   libc="glibc"),
    Platform("aarch64", "linux";   libc="glibc"),
    Platform("x86_64",  "windows"),
]
platforms = expand_cxxstring_abis(platforms)

# The products that we will ensure are always built
products = Product[
    ExecutableProduct("llc", :llc),
    ExecutableProduct("lld", :lld),
    FileProduct("amdgcn/bitcode", :bitcode_path),
]

# Dependencies that must be installed before this package can be built
dependencies = [
    Dependency("Zlib_jll")
]

build_tarballs(ARGS, name, version, sources, script,
               platforms, products, dependencies;
               preferred_gcc_version=v"10", julia_compat="1.6")
