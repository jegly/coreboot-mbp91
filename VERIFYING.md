# Verifying what is actually in the firmware

Scanning a firmware image "for malware" does not really work. Signature
scanners answer "does this look like something already known to be bad", which
is close to useless for a boot payload you compiled yourself.

The question worth answering instead is: **is every byte accounted for by
signed upstream source, plus changes I can read?**

That is answerable, and this file is how.

Re-run this after any rebuild.

---

## 1. GRUB source provenance

The payload is GNU GRUB. Check it came from upstream and is signed.

```bash
G=<coreboot>/payloads/external/GRUB2/grub2
git -C $G rev-parse HEAD
git -C $G describe --tags
```

Expected as of this project:

```
5ca9db22e8ed0dbebb2aec53722972de0680a463
grub-2.12
```

Verify the tag signature:

```bash
gpg --keyserver hkps://keys.openpgp.org --recv-keys BE5C23209ACDDACEB20DB0A28C8189F1988C2166
git -C $G tag -v grub-2.12
```

Want:

```
gpg: Good signature from "Daniel Kiper <dkiper@net-space.pl>"
```

`[unknown]` trust and "not certified with a trusted signature" are expected.
They mean the key is not in your personal web of trust, not that anything is
wrong. Step 2 is how you resolve that.

## 2. Cross-check the fingerprint independently

Never trust a single source for a key. This fingerprint was confirmed against
three separate channels, all agreeing:

```
BE5C 2320 9ACD DACE B20D  B0A2 8C81 89F1 988C 2166
```

1. The signature on the git tag itself
2. GNU's official keyring:
   ```bash
   curl -sSLO https://ftp.gnu.org/gnu/gnu-keyring.gpg
   gpg --no-default-keyring --keyring ./gnu-keyring.gpg --fingerprint 8C8189F1988C2166
   ```
3. The GRUB 2.12 release announcement on the grub-devel list, which prints the
   fingerprint in the body

**Note on expiry:** GNU's keyring shows this key as expired 2023-02-27, while
the 2.12 release was signed 2023-12-21. That is not a problem. The keyring is a
stale snapshot; the owner extended the key, and the live copy expires
2029-04-24. Same key, same fingerprint. gpg raises no expiry warning when
verifying.

## 3. What differs from the signed source

This is the check that would actually catch an injection.

```bash
git -C $G status --porcelain | grep -v '^??'
git -C $G diff --stat
```

Expected for this project: exactly one file.

```
grub-core/term/usb_keyboard.c | 7 ++++++-
1 file changed, 6 insertions(+), 1 deletion(-)
```

That is `patches/0008`, discarding invalid 0xFF keycodes. Read it. It is six
lines. **Anything else appearing here needs explaining before you flash.**

Do the same for coreboot and its submodules:

```bash
git -C <coreboot> status --porcelain | grep -v '^??'
git -C <coreboot>/3rdparty/libgfxinit status --porcelain | grep -v '^??'
git -C <coreboot>/3rdparty/vboot status --porcelain | grep -v '^??'
```

Every modified file should correspond to a patch in `patches/`. There is a
cross-check for this in `UPSTREAMING.md`.

## 4. Enumerate what is baked into the payload

Not a mystery, and not a wildcard. One line, `grub2/Makefile.am:437`:

**Loaded at startup** (`--modules`):

```
ahci pata ehci uhci ohci usb_keyboard usbms part_msdos ext2 fat
at_keyboard part_gpt usbserial_usbdebug cbfs
```

**Packaged, available to insmod** (`--install-modules`):

```
ls linux search configfile normal cbtime cbls memrw iorw minicmd lsmmap
lspci halt reboot hexdump pcidump regexp setpci lsacpi chain test serial
multiboot cbmemc linux16 gzio echo help syslinuxcfg xnu
$(FS_PAYLOAD_MODULES) password_pbkdf2 $(EXTRA_PAYLOAD_MODULES)
```

`FS_PAYLOAD_MODULES` is every filesystem module GRUB builds
(`grub-core/fs.lst`). `EXTRA_PAYLOAD_MODULES` is `CONFIG_GRUB2_EXTRA_MODULES`,
which this project sets to `all_video`.

`password_pbkdf2` being in that list is why the GRUB password works at all.

## 5. Reproducibility

Build twice from the same tag and compare. The payload has been consistently
474,115 bytes across builds (before adding `all_video`).

```bash
cbfstool <rom> print | grep payload
```

A payload that changes size without a config or source change is worth
investigating.

## 6. Verify the built ROM itself

```bash
EXPECTED_DESC=vendor/descriptor-me-denied.bin \
  ./scripts/verify-production-rom.sh coreboot-hardened-spilock.rom
```

Eight checks against the finished image rather than the build inputs: size,
descriptor integrity, FLMSTR1 denying host write, no CONSOLE region, no
CONSOLE_SPI_FLASH, loglevel not 8, no debug FMD, payload present.

---

## What this does not cover

Being honest about the boundaries:

* **coreboot itself** deserves the same treatment as steps 1 to 3. It is a git
  checkout, so the same commands work.
* **The toolchain.** Nothing here defends against a compromised compiler. That
  is the trusting-trust problem and it is not solvable at this level.
* **The Intel ME.** You cannot inspect it, audit it, or meaningfully verify it.
  That is exactly why this project denies it all flash access
  (`FLMSTR2 = 0`) rather than trying to reason about what it does.
* **Apple's flash descriptor.** Configuration data rather than code, and it is
  byte-compared against your own dump in `verify-production-rom.sh`, but it is
  still vendor data you did not write.

The value here is not that it proves the firmware is clean. It is that it
reduces "do I trust this 8 MiB binary" down to "do I trust signed upstream
GRUB, signed upstream coreboot, and six lines I wrote myself". That is a much
smaller question.
