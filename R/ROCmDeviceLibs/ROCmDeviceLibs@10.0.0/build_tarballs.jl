using Pkg
using BinaryBuilder

const NAME = "ROCmDeviceLibs"
const ROCM_PLATFORMS = [AnyPlatform()]
const PRODUCTS = [FileProduct("amdgcn/bitcode/", :bitcode_path)]

# Since ROCm 6.1 the device libraries live in ROCm's LLVM fork, under
# `amd/device-libs`. The commit is the `compiler/amd-llvm` submodule pin of the
# matching ROCm (TheRock) release tag, e.g. `therock-10.0` for ROCm 10.0.
const ROCM_LLVM_GIT = "https://github.com/ROCm/llvm-project"
const ROCM_LLVM_COMMITS = Dict(
    v"10.0.0" => "8f497e0992fb7513f7f78a6f6b6f1056c375e961",
)

# Host LLVM+Clang toolchain used to compile the device libraries to bitcode. It
# must be at least as new as the fork's own LLVM (ROCm 10.0 is based on LLVM 23),
# since the sources use the newest AMDGPU builtins and Clang headers. The
# resulting bitcode is consumed by AMDGPU_LLVM_Backend_jll, whose LLVM this
# should track.
const LLVM_VERSIONS = Dict(
    v"10.0.0" => v"23.1.1",
)

function configure_build(version)
    buildscript = raw"""
    cd ${WORKSPACE}/srcdir/llvm-project/amd/device-libs
    install_license LICENSE.TXT

    mkdir build && cd build
    CMAKE_FLAGS=()
    CMAKE_FLAGS+=(-DCMAKE_INSTALL_PREFIX=${prefix})
    CMAKE_FLAGS+=(-DCMAKE_BUILD_TYPE=Release)
    # `prepare-builtins` must run during the build, so build it with the host toolchain
    CMAKE_FLAGS+=(-DCMAKE_TOOLCHAIN_FILE=${CMAKE_HOST_TOOLCHAIN})
    # Locate the host LLVM/Clang cmake packages from LLVM_full_jll
    CMAKE_FLAGS+=(-DCMAKE_PREFIX_PATH=${host_prefix})
    cmake -GNinja .. ${CMAKE_FLAGS[@]}
    ninja -j${nproc} install
    """

    sources = [GitSource(ROCM_LLVM_GIT, ROCM_LLVM_COMMITS[version])]
    dependencies = [
        HostBuildDependency(PackageSpec(; name="LLVM_full_jll", version=LLVM_VERSIONS[version])),
    ]
    NAME, version, sources, buildscript, ROCM_PLATFORMS, PRODUCTS, dependencies
end

# GCC 10 matches the compiler LLVM_full_jll is built with, which `prepare-builtins`
# links against.
build_tarballs(
    ARGS, configure_build(v"10.0.0")...;
    preferred_gcc_version=v"10",
    julia_compat="1.6")
