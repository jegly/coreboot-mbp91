# Bench checklist — flashing this machine

Read [RECOVERY.md](RECOVERY.md) first. Work through this top to bottom.

---

## The images

| File | When to flash it | Descriptor | Console |
|---|---|---|---|
| `coreboot-hardened-spilock-LOCKED.rom` | **normally** | locked + ME denied everything | none |
| `coreboot-hardened-spilock.rom` | same, without the GRUB password | locked + ME denied everything | none |
| `coreboot-debug.rom` | only if a flash boots to nothing | unlocked | log written into flash |
| `vendor/orig.bin` | to go back to stock, any time | stock | n/a |

**Note on ordering.** Earlier revisions of this file said to flash a
stock-descriptor "production" image first and only then try the hardened one,
so that a failure told you which change caused it. That advice made sense
during bring-up. The hardened descriptor is now proven on this machine across
many boots, so those variants were dropped. If you are bringing up a *different*
board, the staged approach is still the right one and
`vendor/descriptor-me-nowrite.bin` gives you the milder middle step.

**These images write-protect the flash.** Once flashed there is no software
path back: `SMM_BWP` and a protected range cover the whole chip. Every future
flash needs the clip. That is deliberate, but know it before you start.

---

## Before the clip comes out

- [ ] **Copy this whole folder to a USB stick.** It lives on the target's
      LUKS-encrypted SSD; if the machine won't boot, it's unreachable.
- [ ] Confirm the other machine can read the stick.
- [ ] **Verify the image you're about to flash.** Exit 0 and eight green PASS
      lines, or do not proceed. The hardened descriptor is deliberately not the
      stock one, so the checker has to be told which to expect, otherwise it
      fails a check that is doing its job:
      ```
      EXPECTED_DESC=vendor/descriptor-me-denied.bin \
        ./scripts/verify-production-rom.sh coreboot-hardened-spilock-LOCKED.rom
      ```
      If `cbfstool` isn't on PATH, prefix with `CBFSTOOL=<path to cbfstool>`.
      It is built at `build/cbfstool` inside any coreboot tree, including one
      reconstructed by `scripts/setup-tree.sh`.
- [ ] `sha256sum -c ROM-CHECKSUMS.txt`
- [ ] **Prove the programmer can WRITE, not just read.** Read the chip twice,
      confirm the two reads are identical, write the same image back, read
      again and compare. A programmer that only reads is not a recovery path.
- [ ] Keep the pre-flash read as a second copy of stock, independent of
      `vendor/orig.bin`.
- [ ] Note the current EFI firmware password somewhere. Flashing removes it;
      restoring `orig.bin` brings it back.
- [ ] **Disconnect the battery** before attaching the clip. Non-negotiable.

---

## What to expect on first boot

There is **no console**. The only signal is the screen. In rough order of
likelihood:

1. **GRUB appears on the internal panel** — everything worked. Biggest single
   unknown (dual-link LVDS) is resolved.
2. **GRUB appears but won't boot Ubuntu** — good outcome, very recoverable.
   The payload looks for `/boot/grub/grub.cfg` on `sda2`. At the `grub>`
   prompt:
   ```
   ls                                  # find the right device
   set root=(ahci0,gpt2)
   linux /vmlinuz root=/dev/mapper/ubuntu--vg-ubuntu--lv ro
   initrd /initrd.img
   boot
   ```
3. **Screen stays dark** — could be libgfxinit failing on the panel, or
   raminit dying in romstage. Indistinguishable without a log. Check for
   signs of life first (fans spinning, caps-lock LED, machine on the network)
   before assuming it's dead.
4. **No power at all** — most likely the GPIO map, though it was read off this
   machine so this is unlikely.

Boot takes roughly a second, every boot.

(An earlier revision of this file predicted slow boots forever, on the theory
that the locked descriptor would stop coreboot writing `RW_MRC_CACHE` and DRAM
would be retrained every time. That was wrong. The cache is written at
`BS_DEV_ENUMERATE` ON_EXIT, before the lockdown runs at `BS_DEV_RESOURCES`
ON_ENTRY, so it updates normally. See BUILDS.md.)

---

## If it's dark and silent

1. Restore `vendor/orig.bin`, confirm the machine still boots stock. This
   separates "my change is wrong" from "I damaged something".
2. Flash `coreboot-debug.rom`.
3. Power on, let it fail, power off.
4. Read the chip back with the programmer:
   ```
   flashrom -p <programmer> -r readback.bin
   cbfstool readback.bin read -r CONSOLE -f console.log
   ```
5. `console.log` contains coreboot's full boot log at loglevel 8 — including
   raminit's SPD probe and training results, and everything libgfxinit did
   with the panel. That tells you exactly where it stopped.
6. Restore `orig.bin` again while the fix is worked out.

---

## After it boots

- Audio can only be tested through the **headphone jack** — this unit's
  internal speakers and mic are removed.
- `cbmem -c` dumps the coreboot log from RAM. Needs `iomem=relaxed`, which is
  currently on your cmdline; if you restore the hardened cmdline it may stop
  working.
- Runtime options (GPU switching, ME state, SMT) are in
  [USAGE.md](USAGE.md) — changed with `nvramtool`, no reflash needed.
- Installing Ubuntu from a USB stick written with GNOME Disks works out of the
  box. coreboot's stock GRUB payload already carries every filesystem module
  (`FS_PAYLOAD_MODULES` = all of `grub-core/fs.lst`), iso9660 included, so
  nothing had to be added to the payload for this.
- If a hardened image does not boot, the milder fallback is
  `vendor/descriptor-me-nowrite.bin` (`FLMSTR2 = 0x00010000`, the ME keeps
  descriptor read access but loses its own region). Point
  `CONFIG_IFD_BIN_PATH` at it and rebuild. Described in `defconfig-hardened`.
