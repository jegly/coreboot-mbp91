#!/usr/bin/env bash
# Rebuild the coreboot tree for the MacBookPro9,1 port from scratch.
#
# Usage: ./scripts/setup-tree.sh [target-dir]      (default: ./coreboot)
#
# Produces a tree that builds coreboot-hardened-spilock.rom byte-for-byte
# equivalent to the shipped image (modulo the CONFIG_IFD_BIN_PATH string,
# which records the absolute path of your vendor blobs).
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${1:-$PWD/coreboot}"
P="$HERE/patches"

# The commit this port was developed and verified against. Later coreboot may
# work, but has not been tested and the patches may not apply cleanly.
BASE_COMMIT="9ba5cc363a2a11f39df69947cea3f01139acdf78"

echo "==> host dependencies"
echo "    sudo apt install gnat gawk libpci-dev pciutils build-essential \\"
echo "                     flex bison libssl-dev zlib1g-dev"
echo "    gnat is REQUIRED. libgfxinit is Ada, and without it you get no"
echo "    graphics. coreboot will warn and build anyway, so watch for it."
echo

echo "==> fetching coreboot @ $BASE_COMMIT"
mkdir -p "$DEST"; cd "$DEST"
git init -q .
git remote add origin https://review.coreboot.org/coreboot 2>/dev/null || true
git fetch --depth 1 origin "$BASE_COMMIT" || {
	echo "    shallow fetch of that commit failed, falling back to full clone"
	git fetch origin main
}
git checkout -q "$BASE_COMMIT"

echo "==> installing the macbookpro9_1 board"
rm -rf src/mainboard/apple/macbookpro9_1
cp -r "$HERE/board" src/mainboard/apple/macbookpro9_1

echo "==> fetching submodules"
git submodule update --init --depth 1 \
	3rdparty/libgfxinit 3rdparty/libhwbase 3rdparty/vboot

echo "==> applying patches"

# libgfxinit -----------------------------------------------------------------
# 0001: the panel is dual-channel LVDS at 88.75 MHz, below libgfxinit's
#       hardcoded 95 MHz threshold. Without this it is driven single-channel
#       and stays dark.
# 0005: GFX_GMA_IGNORE_PRESENCE_STRAPS was only ever implemented for Haswell.
#       This board's LVDS presence strap does not read as set at cold boot, so
#       without this the port is marked invalid and never programmed. SILENTLY.
git -C 3rdparty/libgfxinit apply "$P/0001-libgfxinit-configurable-lvds-dual-threshold.patch"
git -C 3rdparty/libgfxinit apply "$P/0005-libgfxinit-ironlake-honour-ignore-presence-straps.patch"

# vboot ----------------------------------------------------------------------
# 0003: host tool fails to build on newer GCC (discarded const qualifier).
git -C 3rdparty/vboot apply "$P/0003-vboot-const-strchr-gcc-strictness.patch"

# coreboot -------------------------------------------------------------------
# 0002: Kconfig driving the threshold 0001 introduced.
# 0004: the panel provides NO EDID at all, and libgfxinit's Probe_Port has no
#       fallback. Supplies the real timings.
# 0006: hybrid_graphics.c hardcoded indexed gmux reads, ignoring the board's
#       own gmux_indexed setting. THIS is what caused the black screen: the
#       panel stayed wired to the powered-off dGPU.
git apply "$P/0002-coreboot-gma-kconfig-lvds-dual-threshold.patch"
git apply "$P/0004-lvds-panel-mode-fallback-no-edid.patch"
git apply "$P/0006-apple-hybrid-graphics-dispatch-gmux-access.patch"

# 0007 is a debug printk. Not applied by default. Uncomment to reproduce the
# exact local tree used during bring-up:
# git apply "$P/0007-DEBUG-ONLY-lightup-ok-printk.patch"

echo "==> fetching the GRUB payload source and patching it"
# 0008 lives in GRUB, which coreboot clones on demand. The Makefile has a
# checkout target, so we can fetch it before building rather than after.
make -C payloads/external/GRUB2 checkout >/dev/null 2>&1 || \
	echo "    (GRUB checkout target failed; apply 0008 by hand after the first build)"
if [ -d payloads/external/GRUB2/grub2/grub-core ]; then
	git -C payloads/external/GRUB2/grub2 apply "$P/0008-grub-usb-keyboard-discard-invalid-0xff-keycodes.patch" \
		&& echo "    0008 applied (discards invalid 0xFF keycodes)"
fi

echo "==> writing .config"
sed -e "s|^CONFIG_IFD_BIN_PATH=.*|CONFIG_IFD_BIN_PATH=\"$HERE/vendor/descriptor-me-denied.bin\"|" \
    -e "s|^CONFIG_ME_BIN_PATH=.*|CONFIG_ME_BIN_PATH=\"$HERE/vendor/flashregion_2_intel_me.bin\"|" \
    -e "s|^CONFIG_GRUB2_RUNTIME_CONFIG_FILE=.*|CONFIG_GRUB2_RUNTIME_CONFIG_FILE=\"$HERE/grub.cfg\"|" \
    "$HERE/defconfig-hardened" > .config
make olddefconfig >/dev/null

echo
echo "==> sanity check"
for c in BOOTMEDIA_LOCK_CONTROLLER BOOTMEDIA_LOCK_WHOLE_RO BOOTMEDIA_SMM_BWP \
         DO_NOT_TOUCH_DESCRIPTOR_REGION GFX_GMA_IGNORE_PRESENCE_STRAPS; do
	grep -q "^CONFIG_$c=y" .config && echo "    ok   $c" || echo "    MISSING $c"
done
grep -q 'gmux_indexed" = "0"' src/mainboard/apple/macbookpro9_1/devicetree.cb \
	&& echo "    ok   gmux_indexed = 0" || echo "    MISSING gmux_indexed = 0 -- WILL BLACK SCREEN"

cat <<EOF

==> done. Tree at $DEST

    Build:
        make crossgcc-i386 CPUS=\$(nproc)          # ~40-60 min, first time only
        HOSTCC=gcc-14 CC=gcc-14 CXX=g++-14 make -j\$(nproc) UPDATED_SUBMODULES=1

    All three compiler variables matter. A GNAT/GCC mismatch makes coreboot
    silently build a toolchain without Ada, which means no libgfxinit, which
    means no graphics, and it does NOT fail loudly.

    Verify before flashing:
        EXPECTED_DESC=vendor/descriptor-me-denied.bin \\
          $HERE/scripts/verify-production-rom.sh build/coreboot.rom

    To add the GRUB password afterwards:
        $HERE/scripts/apply-grub-password.sh
EOF
