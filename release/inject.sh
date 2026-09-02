#!/usr/bin/env bash
#
# Build a flashable mbp91-coreboot image by inserting YOUR OWN flash
# descriptor and Intel ME firmware into the published blob-free ROM.
#
# Nothing proprietary is distributed with this project. The two regions below
# come from the dump of your own machine, taken with an external SPI
# programmer:
#
#     flashrom -p <your-programmer> -r mydump.bin
#
# Usage:
#     ./inject.sh mbp91-noblobs.rom mydump.bin flashme.rom [--harden]
#
#   --harden   Also deny the Intel ME every flash permission, including read
#              access to its own region (FLMSTR2 = 0). This is applied to YOUR
#              descriptor here rather than shipping a modified Apple one.
#              Test without it first -- see the warning printed below.
#
set -euo pipefail

NOBLOBS=${1:?usage: inject.sh <noblobs.rom> <yourdump.bin> <out.rom> [--harden]}
DUMP=${2:?usage: inject.sh <noblobs.rom> <yourdump.bin> <out.rom> [--harden]}
OUT=${3:?usage: inject.sh <noblobs.rom> <yourdump.bin> <out.rom> [--harden]}
HARDEN=${4:-}

rd32() { printf "%d" 0x$(od -An -tx4 -j"$2" -N4 -v "$1" | tr -d ' \n'); }

for f in "$NOBLOBS" "$DUMP"; do
	[ -f "$f" ] || { echo "no such file: $f" >&2; exit 1; }
	S=$(stat -c%s "$f")
	[ "$S" -eq 8388608 ] || { echo "$f is $S bytes, expected 8388608 (8 MiB)" >&2; exit 1; }
done

# Your dump must have a real descriptor; the published ROM must not.
SIG=$(od -An -tx4 -j16 -N4 -v "$DUMP" | tr -d ' \n')
[ "$SIG" = "0ff0a55a" ] || {
	echo "ERROR: $DUMP has no valid flash descriptor (sig 0x$SIG)." >&2
	echo "Is this really a full 8 MiB dump of the SPI chip?" >&2
	exit 1; }

NSIG=$(od -An -tx4 -j16 -N4 -v "$NOBLOBS" | tr -d ' \n')
[ "$NSIG" = "ffffffff" ] || {
	echo "ERROR: $NOBLOBS already has a descriptor -- that is not a blob-free image." >&2
	exit 1; }

# Region layout comes from YOUR descriptor.
FLMAP0=$(rd32 "$DUMP" 20)
FLMAP1=$(rd32 "$DUMP" 24)
FRBA=$(( ((FLMAP0 >> 16) & 0xff) << 4 ))
FMBA=$(( (FLMAP1 & 0xff) << 4 ))
FLREG1=$(rd32 "$DUMP" $((FRBA + 4)))
BIOS_BASE=$(( (FLREG1 & 0x1fff) << 12 ))

[ "$BIOS_BASE" -gt 0 ] || { echo "BIOS region base parsed as 0, refusing" >&2; exit 1; }

printf "  your descriptor: FRBA=0x%04x FMBA=0x%04x BIOS region starts 0x%06x\n" \
	"$FRBA" "$FMBA" "$BIOS_BASE"

# BIOS region from the published image, descriptor + ME from your dump.
cp "$NOBLOBS" "$OUT"
dd if="$DUMP" of="$OUT" bs=1M iflag=count_bytes count="$BIOS_BASE" \
   conv=notrunc status=none

if [ "$HARDEN" = "--harden" ]; then
	OLD=$(rd32 "$OUT" $((FMBA + 4)))
	printf '\0\0\0\0' | dd of="$OUT" bs=1 seek=$((FMBA + 4)) conv=notrunc status=none
	NEW=$(rd32 "$OUT" $((FMBA + 4)))
	printf "  FLMSTR2 (Intel ME master): 0x%08x -> 0x%08x\n" "$OLD" "$NEW"
	echo
	echo "  WARNING: the ME is now denied all flash access, including reading the"
	echo "  descriptor. On this board that works, but it is the single most likely"
	echo "  change to stop the machine booting. Flash the non-hardened image first"
	echo "  and confirm it boots before trying this one."
fi

S=$(stat -c%s "$OUT")
[ "$S" -eq 8388608 ] || { echo "output is $S bytes, expected 8388608" >&2; exit 1; }

FSIG=$(od -An -tx4 -j16 -N4 -v "$OUT" | tr -d ' \n')
[ "$FSIG" = "0ff0a55a" ] || { echo "output has no valid descriptor signature" >&2; exit 1; }

echo
echo "  wrote $OUT ($S bytes) -- ready to flash with an external programmer:"
echo "      flashrom -p <your-programmer> -w $OUT"
