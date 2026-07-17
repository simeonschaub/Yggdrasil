# Note that this script can accept some limited command-line arguments, run
# `julia build_tarballs.jl --help` to see a usage message.
using BinaryBuilder, Pkg

name = "ironxrt"
version = v"0.1.0"

# A tiny C-ABI shim over XRT's C++ runtime. The NPU launch flow (register_xclbin
# + hw_context + kernel-by-name) is only exposed as C++ in libxrt_coreutil, so
# IRON.jl cannot reach it by `ccall`ing the XRT C API directly. This wraps just
# that sequence -- open/close, buffer alloc/map/sync, and a single fixed-layout
# run -- behind `extern "C"` entry points. The source is bundled alongside this
# recipe rather than fetched.
sources = [
    DirectorySource("./bundled"),
]

# Build a single shared library. `-fexceptions` is required: XRT reports errors
# by throwing, and the shim catches at the boundary (Julia cannot). The XRT
# headers and import library both come from xrt_jll, staged into the prefix.
script = raw"""
cd ${WORKSPACE}/srcdir
install_license LICENSE
mkdir -p ${libdir}
${CXX} -std=c++17 -O2 -fPIC -fexceptions -shared \
    -I${includedir} \
    ironxrt.cpp \
    -o ${libdir}/libironxrt.${dlext} \
    -L${libdir} -lxrt_coreutil
"""

# x86_64 Linux only, matching xrt_jll (the RyzenAI NPU host). xrt_jll is cxx11
# ABI only, so the shim must be too -- pin the ABI rather than expanding it.
platforms = [
    Platform("x86_64", "linux"; libc = "glibc", cxxstring_abi = "cxx11"),
]

products = [
    LibraryProduct("libironxrt", :libironxrt),
]

# xrt_jll supplies the XRT headers at build time and libxrt_coreutil at both
# build and run time.
dependencies = [
    Dependency("xrt_jll"),
]

# XRT's public headers are C++17.
build_tarballs(
    ARGS, name, version, sources, script, platforms, products, dependencies;
    julia_compat = "1.10", preferred_gcc_version = v"9",
)
