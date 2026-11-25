#!/bin/bash
# Builds the latest libimobiledevice stack (libplist, libimobiledevice-glue,
# libusbmuxd, libtatsu, libirecovery, libimobiledevice, idevicerestore) from
# source into $HOME/apple-restore-tools, without touching system files.
#
# Why: the idevicerestore/libirecovery packaged by Ubuntu (jammy: 1.0.0-3build2,
# from ~2016-2020) can hit "Device did not disconnect. Possibly invalid iBSS."
# during the DFU -> Recovery transition. The current git master has many fixes
# to this handshake. Building from source resolved it for an Apple TV HD.
#
# Requirements (install first, needs sudo once):
#   sudo apt install -y git build-essential autoconf automake libtool \
#     pkg-config meson ninja-build libssl-dev libzip-dev liblzma-dev \
#     libglib2.0-dev libreadline-dev libcurl4-openssl-dev libusb-1.0-0-dev \
#     cmake check usbmuxd libusbmuxd-utils libimobiledevice-utils \
#     libirecovery-1.0-3 libirecovery-common
#
# Usage:
#   bash build_idevicerestore.sh
# Result binaries:
#   $HOME/apple-restore-tools/bin/idevicerestore
#   $HOME/apple-restore-tools/bin/irecovery
#   $HOME/apple-restore-tools/bin/ideviceinfo (and other libimobiledevice tools)

set -e
export PREFIX=$HOME/apple-restore-tools
mkdir -p "$PREFIX"
export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig:$PREFIX/lib/x86_64-linux-gnu/pkgconfig:$PKG_CONFIG_PATH
export LD_LIBRARY_PATH=$PREFIX/lib:$PREFIX/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH
export PATH=$PREFIX/bin:$PATH

WORKDIR=$HOME/idevicerestore-build
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# Build order matters: each depends on the previous ones.
REPOS="libplist libimobiledevice-glue libusbmuxd libtatsu libirecovery libimobiledevice idevicerestore"

for repo in $REPOS; do
  echo "=========================================="
  echo "BUILDING: $repo"
  echo "=========================================="
  if [ ! -d "$repo" ]; then
    git clone --depth 1 "https://github.com/libimobiledevice/$repo.git"
  fi
  cd "$repo"
  ./autogen.sh --prefix="$PREFIX"
  make -j"$(nproc)"
  # UDEVRULESDIR redirect: skips trying to write /lib/udev/rules.d (needs root).
  # The system package (libirecovery-common / usbmuxd) already ships the
  # equivalent udev rules, so this is safe to skip.
  make install UDEVRULESDIR=/tmp/discard_udev_rules
  cd "$WORKDIR"
done

echo "=========================================="
echo "BUILD COMPLETE"
echo "=========================================="
"$PREFIX/bin/idevicerestore" -v
echo
echo "Add this to your shell profile to use the new tools by default:"
echo "  export PATH=\"$PREFIX/bin:\$PATH\""
echo "  export LD_LIBRARY_PATH=\"$PREFIX/lib:\$LD_LIBRARY_PATH\""
