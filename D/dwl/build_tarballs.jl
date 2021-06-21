# Note that this script can accept some limited command-line arguments, run
# `julia build_tarballs.jl --help` to see a usage message.
using BinaryBuilder, Pkg

name = "dwl"
version = v"0.2.1"

# Collection of sources required to complete build
sources = [
    GitSource("https://github.com/djpohly/dwl", "c6f96d5391b43268f05787c4171ddc5ed4cbf0b8"),
    DirectorySource("./bundled"),
]

# Bash recipe for building across all platforms
script = raw"""
cd $WORKSPACE/srcdir/dwl/
atomic_patch ../patches/link_rt.patch
make
make install PREFIX=${prefix}
"""

# These are the platforms we will build for by default, unless further
# platforms are passed in on the command line
platforms = filter!(Sys.islinux, supported_platforms(; experimental=true))

# The products that we will ensure are always built
products = [
    ExecutableProduct("dwl", :dwl),
]

# Dependencies that must be installed before this package can be built
dependencies = Dependency[
    Dependency("Wayland_protocols_jll"),
    Dependency(PackageSpec(; name="wlroots_jll", uuid="3b2e9e63-e3db-5e27-96e9-728b31023cf0", path="/home/simeon/.julia/dev/wlroots_jll")),
    Dependency(PackageSpec(; name="EGL_jll", uuid="5ea76d86-d530-5cf4-b522-b01c04be50f5", path="/home/simeon/.julia/dev/EGL_jll")),
    Dependency("Xorg_xproto_jll"),
]

# Build the tarballs, and possibly a `build.jl` as well.
build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies; preferred_gcc_version=v"5", julia_compat="1.6")
