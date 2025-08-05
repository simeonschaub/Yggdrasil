# Note that this script can accept some limited command-line arguments, run
# `julia build_tarballs.jl --help` to see a usage message.
using BinaryBuilder, Pkg

name = "opencl_kernel_profiler"
version = v"0.0.109"

# Collection of sources required to complete build
sources = [
    GitSource(
        "https://github.com/simeonschaub/opencl-kernel-profiler",
        "a9066671eafca9ac66eeac98119f89ca1fbbccc5"
    ),
]


# Bash recipe for building across all platforms
script = raw"""
apk del cmake
cd $WORKSPACE/srcdir/opencl-kernel-profiler
cmake -B build \
    -DCMAKE_INSTALL_PREFIX=${prefix} \
    -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TARGET_TOOLCHAIN} \
    -DCMAKE_BUILD_TYPE=Release \
    -DOPENCL_HEADER_PATH=${includedir}/CL \
    -DPERFETTO_SDK_PATH=${includedir} \
    -DPERFETTO_LIBRARY=perfetto \
    -DSPIRV_DISASSEMBLY=ON
cmake --build build --parallel ${nproc}
cmake --install build
install_license LICENSE
"""

# These are the platforms we will build for by default, unless further
# platforms are passed in on the command line
platforms = filter(p -> libc(p) == "glibc", supported_platforms())
push!(platforms, Platform("x86_64", "Windows"))
push!(platforms, Platform("aarch64", "macos"))
platforms = expand_cxxstring_abis(platforms)

# The products that we will ensure are always built
products = [
    LibraryProduct("libopencl-kernel-profiler", :libopencl_kernel_profiler),
]

# Dependencies that must be installed before this package can be built
dependencies = [
    BuildDependency(PackageSpec(; name = "OpenCL_Headers_jll", uuid = "a7aa756b-2b7f-562a-9e9d-e94076c5c8ee", path = "$(DEPOT_PATH[1])/dev/OpenCL_Headers_jll")),
    Dependency(PackageSpec(; name = "OpenCL_jll", uuid = "6cb37087-e8b6-5417-8430-1f242f1e46e4", path = "$(DEPOT_PATH[1])/dev/OpenCL_Headers_jll")),
    Dependency("perfetto_jll"),
    Dependency("SPIRV_Tools_jll"),
    HostBuildDependency(PackageSpec(; name = "CMake_jll", version = v"3.24.3")),
]

# Build the tarballs, and possibly a `build.jl` as well.
build_tarballs(
    ARGS, name, version, sources, script, platforms, products, dependencies;
    julia_compat = "1.6", preferred_gcc_version = v"9",
)
