# If it doesn't boot — what to try, in order

The symptom is the only data you have, because the production image has no
console. Work from what you actually observe, not from what you suspect.

**Step zero, always:** restore `vendor/orig.bin` and confirm the machine still
boots stock. This separates "my firmware is wrong" (fixable) from "I damaged
something" (a different problem entirely). Do this before anything else.

---

## First: was the write even good?

Before blaming the port, rule out the flash itself.

```bash
flashrom -p <programmer> -r readback.bin
sha256sum readback.bin            # compare against ROM-CHECKSUMS.txt
```

A mismatch means a bad write, a poor clip contact, or a flaky programmer —
nothing to do with coreboot. Reseat and rewrite.

---

## Symptom A — no power at all. No fan, no LED, nothing.

**Stage:** bootblock, or a bad flash.

Most likely a bad write (see above). If the read-back matches, the suspect is
`gpio.c` — but that was generated from `inteltool -g` on this exact machine,
so it is *unlikely*, not impossible.

**Next:** flash `coreboot-debug.rom` and see whether it produces any console
output at all. If a bootblock-stage failure prevents even that, the flash
console won't have been written either — which is itself informative.

## Symptom B — fans spin, but the screen stays dark

**The most likely failure, and the one the debug image exists for.**

This is either romstage (raminit died) or ramstage (graphics failed), and
those are **indistinguishable from outside the case**. Do not guess between
them.

> ### !!! THE ORDER MATTERS !!!
> The console log exists **only inside the flash chip**. If you restore
> `orig.bin` before reading the chip back, **the log is destroyed** and the
> whole debug cycle was wasted. This happened on the first attempt.
> **Read the chip back BEFORE you reflash anything.**

1. Flash `coreboot-debug.rom`.
2. Power on, let it fail (give it ~30 s), power off.
3. **READ THE CHIP BACK NOW — before restoring anything:**
   ```bash
   flashrom -p <programmer> -r readback.bin
   ```
4. Extract the log:
   ```bash
   cbfstool readback.bin read -r CONSOLE -f console.log
   wc -l console.log        # sanity: should be hundreds of lines, not zero
   ```
5. `console.log` is coreboot's full boot log at loglevel 8. It will show
   raminit's SPD probe and training, and everything libgfxinit did with the
   panel.
6. **Only now** restore `vendor/orig.bin` while the fix is worked out.

### If the log shows raminit failing

Ranked suspects — everything here that was *verified* is listed as such:

| Value | Status | Notes |
|---|---|---|
| `spd_addresses = {0x50, 0, 0x52, 0}` | **verified** by `i2cdetect` | unlikely to be wrong |
| `DRAM_RESET_GATE_GPIO = 28` | **verified** | no longer a suspect: S3 suspend/resume works, which exercises this exact path. (Originally inherited from the 10,1 and only weakly corroborated by gpio28 being a GPIO-mode output driven high on both boards.) |
| DIMM compatibility | 2× matched Samsung M471B1G73QH0-YK0, DDR3L-1600 CL11 dual-rank | 4 ranks total; if training is marginal, try a single DIMM in the channel-0 socket to halve the problem |

### If the log shows graphics failing

| Value | Status | Notes |
|---|---|---|
| dual-link LVDS threshold | **fixed and verified** in the generated Ada (`80000000`) | should be right |
| panel power sequencing delays | **inherited from the 10,1's Retina eDP panel** | **prime suspect.** Wrong delays typically give a slow, flickery or dead panel. The real values can be read from the running vendor firmware via the LVDS/PP registers. |
| gmux mux switching | inherited (`gmux_indexed = 1`, `early_hybrid_graphics()`) | **strong suspect.** If the mux is not switched to the iGPU, the panel stays on the dGPU and the screen is dark *even with perfect libgfxinit*. Under stock firmware this machine has the panel on the dGPU (`boot_vga=1` on `01:00.0`). |
| backlight | i915 reports `Skipping intel_backlight registration`; gmux owns it | a lit-but-black panel means backlight, not modesetting |

**Useful distinction:** shine a torch at the screen at an angle. If you can see
a faint image, the panel is being driven and the *backlight* is off — a
different and much easier problem than no signal at all.

## Symptom C — GRUB appears but Ubuntu won't boot

**Best case.** The hard parts all worked. No reflash needed — fix it at the
`grub>` prompt:

```
ls                                    # find the device
set root=(ahci0,gpt2)                 # /boot is sda2
linux /vmlinuz root=/dev/mapper/ubuntu--vg-ubuntu--lv ro
initrd /initrd.img
boot
```

Once booted, `cbmem -c` dumps the whole coreboot log from RAM — no clip
needed. That is the point at which everything becomes easy to debug.

## Symptom D — screen lights but the image is wrong

Garbled, wrong resolution, or shifted. Panel timing. The correct values are
known and recorded in `notes/hardware-probe.txt`:

```
1440x900 @ 88.75 MHz
H: 1440 / 1488 / 1520 / 1600      V: 900 / 903 / 909 / 926
negative H sync, negative V sync
```

---

## What we'd change first, if forced to guess with no log

In order:

1. **`DRAM_RESET_GATE_GPIO`** — the only inherited value on the critical boot
   path that isn't corroborated by this machine's own hardware.
2. **Panel power sequencing** — inherited from a different panel technology
   entirely (eDP vs LVDS). Derive the real values by reading the panel power
   sequencing registers under the vendor firmware rather than inheriting them.
3. **gmux switching behaviour** — verify `early_hybrid_graphics()` actually
   moves the mux on this board rather than assuming the 10,1's sequence.

But guessing costs a clip cycle each time. **Reading the log costs one.**
That is the whole reason the debug image exists — use it before guessing.
