#!/usr/bin/env bash
#
# Turn a locally-built coreboot ROM into a PUBLISHABLE image by erasing the
# two regions that must never be redistributed:
#
#   Flash descriptor  - Apple's, and carries machine-specific data
#   Intel ME          - proprietary; contains serial number / UUIDs
#
# What is left is the BIOS region: our own coreboot build, which contains no
# personal data and no vendor code.
#
# Region boundaries are read FROM THE DESCRIPTOR, not hardcoded.
#
# Usage: ./make-noblobs.sh coreboot.rom mbp91-noblobs.rom
#
set -euo pipefail

SRC=${1:?usage: make-noblobs.sh <built.rom> <output-noblobs.rom>}
DST=${2:?usage: make-noblobs.sh <built.rom> <output-noblobs.rom>}

rd32() { printf "%d" 0x$(od -An -tx4 -j"$2" -N4 -v "$1" | tr -d ' \n'); }

[ -f "$SRC" ] || { echo "no such file: $SRC" >&2; exit 1; }

SIZE=$(stat -c%s "$SRC")
[ "$SIZE" -eq 8388608 ] || { echo "expected an 8 MiB image, got $SIZE bytes" >&2; exit 1; }

SIG=$(od -An -tx4 -j16 -N4 -v "$SRC" | tr -d ' \n')
[ "$SIG" = "0ff0a55a" ] || { echo "no valid flash descriptor signature (got 0x$SIG)" >&2; exit 1; }

# Locate the BIOS region from the descriptor's region table.
FLMAP0=$(rd32 "$SRC" 20)
FRBA=$(( ((FLMAP0 >> 16) & 0xff) << 4 ))
FLREG1=$(rd32 "$SRC" $((FRBA + 4)))
BIOS_BASE=$(( (FLREG1 & 0x1fff) << 12 ))

[ "$BIOS_BASE" -gt 0 ] || { echo "BIOS region base parsed as 0, refusing" >&2; exit 1; }

printf "  BIOS region starts at 0x%06x -- blanking everything below it\n" "$BIOS_BASE"

# Copy the whole image, then 0xFF-fill everything below the BIOS region.
# (head must be UPSTREAM of tr here: the reverse order kills tr with SIGPIPE,
# which `set -o pipefail` turns into a silent early exit.)
cp "$SRC" "$DST"
head -c "$BIOS_BASE" /dev/zero | tr '\0' '\377' | dd of="$DST" conv=notrunc status=none

OUT=$(stat -c%s "$DST")
[ "$OUT" -eq "$SIZE" ] || { echo "size mismatch: $OUT != $SIZE" >&2; exit 1; }

# Prove the blobs are actually gone: nothing but 0xFF below BIOS_BASE.
NONFF=$(head -c "$BIOS_BASE" "$DST" | tr -d '\377' | wc -c)
[ "$NONFF" -eq 0 ] || {
	echo "ERROR: blanked area still holds $NONFF non-0xFF bytes" >&2
	exit 1; }

echo "  wrote $DST ($OUT bytes)"
echo "  descriptor + ME erased; BIOS region preserved."
echo
echo "  Before publishing, confirm nothing personal survives in the BIOS region:"
echo "      strings '$DST' | grep -inE 'pbkdf2|serial|\\\$USER|\\\$HOSTNAME'"

# ---------------------------------------------------------------------------
# WHY THIS BLANKS BY REGION RATHER THAN SCRUBBING KNOWN STRINGS
#
# The flash descriptor on this board carries an OEM section holding a 32-char
# hex identifier -- discovered only by chance, late, via `ifdtool -d`. Nobody
# had thought to grep for it, because nobody knew it existed.
#
# Erasing whole regions removes everything inside them, including fields no
# one has looked for yet. A string-scrub only ever removes what you already
# knew to search for. Do not "optimise" this into a targeted scrub.
# ---------------------------------------------------------------------------
