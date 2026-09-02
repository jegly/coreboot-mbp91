#!/usr/bin/env bash
#
# Pre-flash safety check for the PRODUCTION image.
#
# Refuses any ROM that carries debug-image traits. Run this immediately before
# putting the clip on. Exit status 0 = safe to flash.
#
#   ./verify-production-rom.sh /path/to/coreboot.rom
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROM="${1:-}"
VENDOR="$HERE/vendor/orig.bin"
CBFSTOOL="${CBFSTOOL:-$(command -v cbfstool || echo ./coreboot/build/cbfstool)}"

fail=0
pass() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail=1; }
warn() { printf '  \033[33mWARN\033[0m  %s\n' "$1"; }

[ -n "$ROM" ] || { echo "usage: $0 <coreboot.rom>"; exit 2; }
[ -f "$ROM" ] || { echo "no such file: $ROM"; exit 2; }

echo "Verifying $ROM as a PRODUCTION image"
echo

# 1. exact size
sz=$(stat -c%s "$ROM")
[ "$sz" = 8388608 ] && pass "size is exactly 8388608 bytes" \
                    || bad "size is $sz, expected 8388608"

# 2. descriptor must match the one this variant is supposed to carry.
#    Default: byte-identical to the vendor's LOCKED descriptor.
#    For the hardened variant (FLMSTR2 zeroed) run with:
#       EXPECTED_DESC=vendor/descriptor-me-denied.bin ./verify-production-rom.sh ...
EXPECTED_DESC="${EXPECTED_DESC:-}"
if [ -n "$EXPECTED_DESC" ]; then
	if [ -f "$EXPECTED_DESC" ]; then
		if cmp -s -n 4096 "$ROM" "$EXPECTED_DESC"; then
			pass "descriptor matches $(basename "$EXPECTED_DESC")"
		else
			bad "descriptor does NOT match $(basename "$EXPECTED_DESC")"
		fi
	else
		bad "EXPECTED_DESC file not found: $EXPECTED_DESC"
	fi
elif [ -f "$VENDOR" ]; then
	if cmp -s -n 4096 "$ROM" "$VENDOR"; then
		pass "descriptor is byte-identical to vendor/orig.bin (locked)"
	else
		bad "DESCRIPTOR DIFFERS from vendor/orig.bin -- is this the debug image?"
	fi
else
	warn "vendor/orig.bin missing, cannot compare descriptor"
fi

# 3. master section must still deny host writes
if command -v ifdtool >/dev/null; then
	mstr=$(ifdtool -d "$ROM" 2>/dev/null | sed -n '/Found Master Section/,/Requester ID/p')
	if echo "$mstr" | grep -q "Host CPU/BIOS Region Write Access: *disabled"; then
		pass "FLMSTR1 denies host CPU write to the BIOS region"
	else
		bad "FLMSTR1 ALLOWS host writes -- unlocked descriptor, this is a DEBUG image"
	fi
else
	warn "ifdtool not found, skipping master section check"
fi

# 4. no CONSOLE region in the flash map
if [ -x "$CBFSTOOL" ] || command -v cbfstool >/dev/null; then
	regions=$("$CBFSTOOL" "$ROM" layout -w 2>/dev/null || true)
	if echo "$regions" | grep -qw "CONSOLE"; then
		bad "FMAP contains a CONSOLE region -- this is the DEBUG image"
	else
		pass "no CONSOLE region in the flash map"
	fi

	# 5. embedded .config must not enable the flash console or loglevel 8
	cfg=$(mktemp)
	if "$CBFSTOOL" "$ROM" extract -n config -f "$cfg" >/dev/null 2>&1; then
		if grep -q "^CONFIG_CONSOLE_SPI_FLASH=y" "$cfg"; then
			bad "CONFIG_CONSOLE_SPI_FLASH=y in the embedded config -- DEBUG image"
		else
			pass "CONFIG_CONSOLE_SPI_FLASH not enabled"
		fi
		if grep -q "^CONFIG_DEFAULT_CONSOLE_LOGLEVEL_8=y" "$cfg"; then
			warn "loglevel 8 (Spew) -- expected for debug, not production"
		else
			pass "console loglevel is not 8"
		fi
		if grep -q "^CONFIG_FMDFILE=\"\"" "$cfg" || ! grep -q "^CONFIG_FMDFILE=" "$cfg"; then
			pass "no custom FMDFILE (default flash layout)"
		else
			fmd=$(grep "^CONFIG_FMDFILE=" "$cfg")
			echo "$fmd" | grep -q "debug.fmd" \
				&& bad "FMDFILE points at debug.fmd -- DEBUG image" \
				|| warn "custom FMDFILE set: $fmd"
		fi
		if grep -q "^CONFIG_PAYLOAD_NONE=y" "$cfg"; then
			bad "PAYLOAD_NONE -- this ROM has no payload and will NOT boot"
		else
			pass "a payload is present"
		fi
	else
		warn "could not extract embedded config from CBFS"
	fi
	rm -f "$cfg"
else
	warn "cbfstool not found, skipping FMAP/config checks (set CBFSTOOL=)"
fi

echo
if [ "$fail" = 0 ]; then
	printf '\033[32m==> SAFE TO FLASH as production\033[0m\n'
	exit 0
else
	printf '\033[31m==> DO NOT FLASH. This looks like a debug or broken image.\033[0m\n'
	exit 1
fi
