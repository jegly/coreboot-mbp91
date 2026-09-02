# What each ROM in this folder is

Definitive per-image reference. Generated from the actual defconfigs, not from
memory. For the order to flash them in, see [FLASHING.md](FLASHING.md).

> **Read section 6 first.** Sections 1 to 4 below describe the original
> bring-up image set and are kept as history, because the reasoning in them
> still explains *why* each option is set. They are **not** current
> instructions. The images that actually exist now are listed in section 6,
> and `coreboot-production.rom` / `coreboot-hardened.rom` are gone.

Every image is **8,388,608 bytes exactly** and built from the same board source
in `board/`. Checksums in `ROM-CHECKSUMS.txt`.

---

## What all three share

```
CONFIG_BOARD_APPLE_MACBOOKPRO9_1=y
CONFIG_MAINBOARD_USE_LIBGFXINIT=y          native Intel graphics, no VGA option ROM
CONFIG_PAYLOAD_GRUB2=y                     GRUB 2.12 in the ROM
CONFIG_GRUB2_EXTRA_MODULES=""              no modules added; stock already has them all
CONFIG_CPU_MICROCODE_CBFS_NONE=y           no microcode blob; Ubuntu loads it from initramfs
CONFIG_HAVE_IFD_BIN=y / CONFIG_HAVE_ME_BIN=y
CONFIG_ME_BIN_PATH=<vendor me region, me_cleaner'd to FTPR only>
```

The GRUB payload is stock coreboot's `default_payload.elf`. Nothing was added
to it. Its `FS_PAYLOAD_MODULES` already pulls in every filesystem module GRUB
builds — iso9660, ext2, fat, exfat, ntfs, btrfs, xfs, zfs, udf and more — so
installer USBs and ordinary disks are all readable out of the box.

Also common to all three, from the board Kconfig:
`GFX_GMA_PANEL_1_ON_LVDS`, `GFX_GMA_LVDS_DUAL_THRESHOLD=80000000` (the
dual-link fix), `spd_addresses = {0x50, 0, 0x52, 0}`, Thunderbolt / FireWire /
WiFi root ports off, `sata_port_map = 0x3`.

---

## 1. `coreboot-production.rom` — flash this one

**The normal image.** Built from `defconfig`.

```
CONFIG_IFD_BIN_PATH=<vendor descriptor, unmodified>
CONFIG_DO_NOT_TOUCH_DESCRIPTOR_REGION=y
```

- Descriptor **byte-identical to `vendor/orig.bin`**: `FLMSTR1 = 0x00030000`
  (host CPU denied write to every region), `FLMSTR2 = 0x04050000` (stock).
- No console of any kind. A pre-graphics failure is silent.
- `DO_NOT_TOUCH_DESCRIPTOR_REGION` is **critical** — coreboot's default is
  `UNLOCK_FLASH_REGIONS`, which runs `ifdtool -u` and would leave the OS able
  to rewrite its own firmware.

Verify:
```bash
./scripts/verify-production-rom.sh coreboot-production.rom
```

---

## 2. `coreboot-hardened.rom` — only after production is proven

**Production plus a stricter descriptor.** Built from `defconfig-hardened`.
Differs from production by exactly one line:

```
CONFIG_IFD_BIN_PATH=<vendor/descriptor-me-denied.bin>
```

- `FLMSTR1 = 0x00030000` — unchanged, host still denied write everywhere.
- `FLMSTR2 = 0x00000000` — **the ME is denied everything**, including its own
  region and even read access to the descriptor. Stock is `0x04050000`.
- Everything else is identical to production, bit for bit in configuration.

**EXPERIMENTAL — may not boot.** The ME normally reads the descriptor to
locate its own region during early platform init. Denying that may leave it
unable to start, and ME failure on Ivy Bridge can affect platform power
sequencing. On this machine the ME is already me_cleaner'd to FTPR with
`AltMeDisable` set, so it barely runs — but "barely" is not "not at all".

If it does not boot, the milder fallback is
`vendor/descriptor-me-nowrite.bin` (`FLMSTR2 = 0x00010000`): the ME keeps
descriptor read but loses all access to its own region. Point
`CONFIG_IFD_BIN_PATH` at that instead and rebuild.

Verify (needs to be told which descriptor to expect, or it fails a check that
is doing its job):
```bash
EXPECTED_DESC=vendor/descriptor-me-denied.bin \
  ./scripts/verify-production-rom.sh coreboot-hardened.rom
```

---

## 3. `coreboot-debug.rom` — only if production boots to nothing

**Throwaway diagnostic image.** Built from `defconfig-debug`. Differs from
production by six lines:

```
CONFIG_UNLOCK_FLASH_REGIONS=y              (production: DO_NOT_TOUCH_DESCRIPTOR_REGION)
CONFIG_CONSOLE_SPI_FLASH=y
CONFIG_CONSOLE_SPI_FLASH_BUFFER_SIZE=0x20000
CONFIG_DEFAULT_CONSOLE_LOGLEVEL_8=y        (Spew)
CONFIG_FMDFILE="src/mainboard/apple/macbookpro9_1/debug.fmd"
```

- Descriptor **unlocked** (`FLMSTR1 = 0xffff0000`). Required: coreboot cannot
  write a log to flash if the host is denied write access.
- Custom flash layout adds a **`CONSOLE` region, 128 KB at 0x1A0000**.
- coreboot writes its entire boot log there at maximum verbosity.

This is safe **only** because it is used on an already-non-booting machine —
there is nothing left to protect at that point — and is replaced by production
or `vendor/orig.bin` immediately afterwards. It must never be left on the
machine.

Recover the log after a failed boot:
```bash
flashrom -p <programmer> -r readback.bin
cbfstool readback.bin read -r CONSOLE -f console.log
```

`console.log` contains raminit's SPD probe and training results and everything
libgfxinit did with the panel — i.e. exactly which of the two unproven paths
failed.

**It deliberately fails the production verifier on five checks.** That is the
guard working, not a fault.

---

## 4. `vendor/orig.bin` — not a build

Byte-for-byte copy of the stock Apple EFI as dumped from this machine
(`233.0.0.0.0`), ME already me_cleaner'd, descriptor locked. The way back, at
any time. See [RECOVERY.md](RECOVERY.md).

---

## Rebuilding any of them

```bash
cd coreboot-tree                     # or reconstruct with scripts/setup-tree.sh
cp ../defconfig .config              # or defconfig-hardened / defconfig-debug
make olddefconfig
HOSTCC=gcc-14 CC=gcc-14 CXX=g++-14 make -j4 UPDATED_SUBMODULES=1
```

All three compiler variables matter, and `UPDATED_SUBMODULES=1` is not
optional — without it coreboot tries to fetch every submodule on each build
and hangs. It re-checks every submodule otherwise.

Changing `CONFIG_GRUB2_EXTRA_MODULES` wipes `payloads/external/GRUB2/grub2/build`
and re-bootstraps GRUB, which costs ~20 minutes per variant.

---

## 5. `coreboot-hardened-spilock.rom` — current recommended daily image

**Hardened, plus the PCH-level SPI write locks.** Differs from
`coreboot-hardened.rom` by three lines:

```
CONFIG_BOOTMEDIA_LOCK_CONTROLLER=y
CONFIG_BOOTMEDIA_LOCK_WHOLE_RO=y
CONFIG_BOOTMEDIA_SMM_BWP=y
```

### Why this exists

`flashrom -p internal --flash-name` on the running machine reported:

```
FREG1: BIOS region (0x00190000-0x007fffff) is read-write.
```

Descriptor master permissions (FLMSTR) protect regions from *other* masters --
they stop the ME reaching the BIOS region and stop the host reaching the ME
region, both of which were verified working. But a master's access to its
*own* region is not gated there. Without these three options, root on the
running OS could overwrite coreboot itself.

### What each does

| Setting | Effect |
|---|---|
| `BIOSWE=0` | host writes to the BIOS region refused |
| `BLE=1` | setting BIOSWE raises an SMI so firmware clears it again |
| `SMM_BWP=1` | writes honoured only in SMM -- closes the Speed Racer race (CVE-2014-8273) |
| PR0-PR4 + FLOCKDN | SPI controller refuses the range outright; frozen until power cycle |

### Verified before building (not assumed)

- `spi_finalize_ops()` is called from `bd82x6x/lpc.c:636`
- `spi_set_smm_only_flashing()` is gated on `SOUTHBRIDGE_INTEL_COMMON_SPI_ICH9`,
  which this board selects
- PR registers implemented: `ICH9_SPI_FPR_*`, `.flash_protect = spi_flash_protect`
- Lockdown runs at `BS_DEV_RESOURCES` ON_ENTRY; FLOCKDN is set later at device
  finalize, so ranges are written *then* frozen

Verified after building: 3 `BM-LOCKDOWN` strings in the LZMA-decompressed
ramstage extracted from the finished ROM.

### RAM training cache — not a problem, ordering handles it

`CONFIG_CACHE_MRC_SETTINGS=y`, so RAM training data lives in `RW_MRC_CACHE`
(offset 0x700000), inside the write-protected range. This is safe, because
coreboot sequences the two deliberately:

```
BS_DEV_ENUMERATE  ON_EXIT   -> finalize_mrc_cache()          (mrc_cache.c:744)
BS_DEV_RESOURCES  ON_ENTRY  -> boot_device_security_lockdown() (lockdown.c:70)
```

The cache is written *before* the lock is applied, on every boot. That pairing
is what lockdown.c's "Keep in sync with mrc_cache.c" comment refers to; the
`#if CONFIG(MRC_WRITE_NV_LATE)` branch moves both to `BS_OS_RESUME_CHECK`
together. `MRC_WRITE_NV_LATE` is not set here.

So swapping the RAM retrains once and caches normally. No reflash needed.

(An earlier revision of this file claimed a RAM swap would force retraining on
every boot. That was wrong -- it assumed the lock was applied before the cache
write without checking the boot-state order.)

### Expected change after flashing

`sudo fwupdmgr security` should flip these from red to green:

```
SPI write:        Enabled   -> Disabled
SPI lock:         Disabled  -> Enabled
SPI BIOS region:  Unlocked  -> Locked
```

and `flashrom -p internal --flash-name` should report FREG1 as **read-only**.

**This is one-way from software.** After flashing, the only way to change the
firmware is an external programmer -- which is already how this board is
flashed, so nothing is lost.

### Both descriptor variants exist with the SPI locks

The three lock options are independent of which descriptor is used, so both
were built:

| Image | Descriptor | FLMSTR2 | SPI locks | GRUB password |
|---|---|---|---|---|
| `coreboot-production-spilock.rom` | stock Apple | `0x04050000` | yes | no |
| `coreboot-production-spilock-LOCKED.rom` | stock Apple | `0x04050000` | yes | yes |
| `coreboot-hardened-spilock.rom` | ME-denied | `0x00000000` | yes | no |
| `coreboot-hardened-spilock-LOCKED.rom` | ME-denied | `0x00000000` | yes | yes |

`production-spilock` is the safer fallback: it has the same flash-write
protection but leaves the ME its stock permissions, so it isolates the SPI
lock change from the ME change. If a locked image ever fails to boot, flashing
this one distinguishes "the locks broke it" from "denying the ME broke it".

The embedded `etc/grub.cfg` is byte-identical across both LOCKED images.

### Confirmed working — actual output after flashing

`sudo fwupdmgr security`:

```
✔ SPI write:                     Disabled
✔ SPI lock:                      Enabled
✔ SPI BIOS region:               Locked

Host Security Events
  ✔ SPI write changed: Enabled → Disabled
  ✔ SPI lock changed: Disabled → Enabled
  ✔ SPI BIOS region changed: Unlocked → Locked
```

`sudo flashrom -p internal --flash-name`:

```
Enabling flash write... Warning: BIOS region SMM protection is enabled!
PR0: Warning: 0x00000000-0x007fffff is read-only.
```

`PR0` covers the **entire 8 MiB** -- descriptor, ME, BIOS and RW_MRC_CACHE --
because `boot_device_ro()` returns the whole memory-mapped flash on this
platform, not just the BIOS region.

**Do not judge this by `FREG1`.** In the same output it still reads:

```
FREG1: BIOS region (0x00190000-0x007fffff) is read-write.
```

FREG lines come from FRAP, which reflects the descriptor, and the descriptor
never gates a master out of its own region. `FREG1` reads read-write on this
board no matter what the locks are set to -- including under stock Apple
firmware. Seeing `PR0: read-only` and `FREG1: read-write` side by side in one
run is the clearest demonstration of the two-layer split.

### Descriptor integrity, verified byte by byte

`coreboot-hardened-spilock.rom` versus the stock backup
(`mbpfit-MOD-hardened.bin`), comparing the full 4096-byte descriptor:

```
total differing bytes: 2
  offset 0x0066:  0x05 -> 0x00
  offset 0x0067:  0x04 -> 0x00     (FLMSTR2: 0x04050000 -> 0x00000000)
```

Field by field, with windows chosen not to overlap the master section at 0x60:

```
header/FLMAP     IDENTICAL     FLMSTR1          IDENTICAL
FCBA component   IDENTICAL     FLMSTR2          DIFFERS  <- the intended change
FRBA regions     IDENTICAL     FLMSTR3          IDENTICAL
PCH straps       IDENTICAL     ME VSCC table    IDENTICAL
OEM section      IDENTICAL     0x0070-0x0FFF    IDENTICAL
```

Everything that would misconfigure or brick the board if damaged -- PCH soft
straps, the ME VSCC table, region map, component density, AltMeDisable -- came
through untouched. Given that coreboot's *default* is `UNLOCK_FLASH_REGIONS`,
which would rewrite FLMSTR1 to `0xffff0000`, this is worth confirming on every
build.

Note `FLMSTR1` is identical between stock and coreboot. Both read
"Host CPU/BIOS Region Write Access: disabled". That setting was therefore never
a difference between the two firmwares, and could never explain any difference
in flash-write behaviour between them.

**Watch the window boundaries when spot-checking.** A first pass using 64-byte
windows from 0x0030 and 0x0040 reported both as DIFFERS; both windows run past
0x0060 and swallow the FLMSTR2 bytes. The byte-level `cmp` is authoritative.

---

## 6. Current images (production variants dropped)

The stock-descriptor "production" variants were removed. The hardened
descriptor is proven on this machine, so a milder fallback stopped earning its
place. The fallbacks that matter are:

* `vendor/orig.bin` - stock Apple firmware, the real way back
* whichever hardened image is currently known-good on the machine

### What is in this build

Built on top of `coreboot-hardened-spilock`, adding three things:

| Change | Where | Status |
|---|---|---|
| `modprobe.blacklist=mei,mei_me` on both USB installer entries | `grub.cfg` | **verified on hardware** at the GRUB prompt before baking in |
| `CONFIG_GRUB2_EXTRA_MODULES="all_video"` | defconfigs | **untested**, reasoned from GRUB's module loader |
| `usb_keyboard.c` discards invalid 0xFF keycodes | `patches/0008` | **untested** |

**The last two are unverified.** Flash and check before trusting them:

* the `all_video.mod not found` message should be gone at boot
* the `unknown key 0xff detected` flood should be gone with a USB stick
  inserted at power-on

Evidence `all_video` was actually added: the payload grew from 474115 to
477184 bytes. `strings` on the ROM does **not** work for this -- it returns
zero for `password_pbkdf2` and `iso9660` too, both of which are definitely
present. Compare payload sizes, not strings; this mistake has now been made twice.

### Images

| Image | Descriptor | Locks | Password |
|---|---|---|---|
| `coreboot-hardened-spilock-LOCKED.rom` | ME denied | yes | yes |
| `coreboot-hardened-spilock.rom` | ME denied | yes | no |
| `coreboot-debug.rom` | unlocked | no | no |

The debug image stays for diagnostics only. It deliberately fails the
production verifier.
