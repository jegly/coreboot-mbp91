# RECOVERY — restoring the stock firmware

If the machine will not boot after flashing coreboot, this is the way back.

## The known-good image

```
vendor/orig.bin      8388608 bytes (8 MiB)
sha256  b77e97394ab20b3070c98f1abbf3ba48f3ae432e396225c9487016eecef19864
```

This is a byte-for-byte copy of what the machine was running when this folder
was created — Apple EFI `233.0.0.0.0`, with the ME already me_cleaner'd and the
descriptor locked. It boots. Verify before use:

```bash
cd vendor && sha256sum -c SHA256SUMS
```

## Flashing it back

Internal flashing is impossible on this machine — `FLMSTR1` in the descriptor
denies the host CPU write access to every region, including the BIOS region.
There is no software route back. It must be the external programmer.

1. **Disconnect the battery** before attaching the clip. Non-negotiable.
2. Attach the SOIC-8 clip to the 8 MiB Macronix flash chip.
3. Verify you can *read* first, and that the read matches a second read:
   ```bash
   flashrom -p <programmer> -r read1.bin
   flashrom -p <programmer> -r read2.bin
   cmp read1.bin read2.bin        # must be identical before you write anything
   ```
4. Write and verify:
   ```bash
   flashrom -p <programmer> -w vendor/orig.bin
   ```

## Before the first coreboot flash — do these

- [ ] Copy this entire folder to a **USB stick**. It lives on the target's
      LUKS-encrypted internal disk; if the machine won't boot, it is gone.
- [ ] Confirm the programmer can **write**, not just read. Read the chip, write
      the identical image back, read again, compare. A programmer that only
      reads is not a recovery path.
- [ ] Note the current EFI firmware password somewhere safe. Flashing coreboot
      removes it, but restoring `orig.bin` brings it back.
- [ ] Keep `read1.bin` from step 3 as a second independent copy.

## If it boots but you can't see anything

The internal LVDS panel is the only guaranteed display on this model — there is
no HDMI port, and the mini-DP output runs through the Thunderbolt controller
which is left disabled. So "no picture" is the expected first-failure mode and
does not necessarily mean the board is dead.

Before assuming a brick, check for signs of life: fans spinning, caps-lock LED
responding, the machine appearing on the network, or a USB debug dongle on the
right-hand port (`CONFIG_USBDEBUG_HCD_INDEX=0`). coreboot console over usbdebug
is the intended way to debug this exact situation, and it is worth having the
dongle working *before* the first flash.
