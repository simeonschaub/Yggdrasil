# Note that this script can accept some limited command-line arguments, run
# `julia build_tarballs.jl --help` to see a usage message.
using BinaryBuilder, Pkg

name = "wlroots"
version = v"0.13.0"

# Collection of sources required to complete build
sources = [
    GitSource("https://github.com/swaywm/wlroots", "69c71dbc8afecc5da5c800cdc1475185064b4ac4"),
    DirectorySource("./bundled"),
]

# Bash recipe for building across all platforms
script = raw"""
cd $WORKSPACE/srcdir/wlroots/
mkdir build
cd build

# update meson
sed -i -e 's/v[[:digit:]]\..*\//edge\//g' /etc/apk/repositories
apk update
apk upgrade --update-cache --available --latest || true
apk add meson || true

PKG_CONFIG_SYSROOT_DIR="" meson -D werror=false -D c_std=gnu11 ../ --cross-file="${MESON_TARGET_TOOLCHAIN}"
ninja -j${nproc}
ninja install
"""

# These are the platforms we will build for by default, unless further
# platforms are passed in on the command line
platforms = filter!(Sys.islinux, supported_platforms(; experimental=true))

# The products that we will ensure are always built
products = [
    LibraryProduct("libwlroots", :libwlroots),
]

# Dependencies that must be installed before this package can be built
dependencies = Dependency[
    Dependency("Wayland_jll"),
    Dependency("Wayland_protocols_jll"),
    Dependency(PackageSpec(; name="EGL_jll", uuid="5ea76d86-d530-5cf4-b522-b01c04be50f5", path="/home/simeon/.julia/dev/EGL_jll")),
    Dependency("libdrm_jll"),
    Dependency(PackageSpec(; name="libevdev_jll", uuid="2db6ffa8-e38f-5e21-84af-90c45d0032cc", path="/home/simeon/.julia/dev/libevdev_jll")),
    Dependency(PackageSpec(; name="libinput_jll", uuid="36db933b-70db-51c0-b978-0f229ee0e533", path="/home/simeon/.julia/dev/libinput_jll")),
    Dependency("xkbcommon_jll"),
    Dependency("eudev_jll"),
    Dependency("Pixman_jll"),
    Dependency("seatd_jll"),
]

# Build the tarballs, and possibly a `build.jl` as well.
build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies; preferred_gcc_version=v"7", julia_compat="1.6")
