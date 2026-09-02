#!/usr/bin/env bash
#
# Insert your GRUB password hash into the config and build password-protected
# ROMs. Your password and its hash never leave this machine.
#
# Usage:
#   1. grub-mkpasswd-pbkdf2          <- copy the grub.pbkdf2.sha512... line
#   2. ./apply-grub-password.sh      <- paste it when asked
#
set -euo pipefail

W=$PROJECT
B=$PROJECT
CBFSTOOL=$COREBOOT/build/cbfstool

echo "Paste the full grub.pbkdf2.sha512... line from grub-mkpasswd-pbkdf2:"
read -r HASH

case "$HASH" in
	grub.pbkdf2.sha512.*) ;;
	*) echo "That doesn't look like a pbkdf2 hash. Aborting."; exit 1;;
esac

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
sed "s|REPLACE_WITH_YOUR_PBKDF2_HASH|$HASH|" "$W/grub-locked.cfg" > "$TMP"

grep -q REPLACE_WITH "$TMP" && { echo "Placeholder not replaced. Aborting."; exit 1; }
echo "  hash inserted ok"

# Build locked copies of the two bootable images, leaving the originals intact.
for v in production hardened; do
	src="$B/coreboot-$v.rom"
	dst="$B/coreboot-$v-LOCKED.rom"
	[ -f "$src" ] || { echo "  missing $src, skipping"; continue; }
	cp "$src" "$dst"
	"$CBFSTOOL" "$dst" remove -n etc/grub.cfg >/dev/null
	"$CBFSTOOL" "$dst" add -f "$TMP" -n etc/grub.cfg -t raw >/dev/null
	echo "  built $(basename "$dst")  $(stat -c%s "$dst") bytes"
done

cd "$B" && sha256sum coreboot-*LOCKED.rom > ROM-CHECKSUMS-LOCKED.txt
echo
echo "Done. Password-protected images:"
sed 's/^/  /' ROM-CHECKSUMS-LOCKED.txt
echo
echo "The un-passworded originals are untouched -- keep them as your way back"
echo "in if you ever forget the password."
