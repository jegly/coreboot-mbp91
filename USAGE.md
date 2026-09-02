# Operating this firmware once it's flashed

Practical knobs and workflows. Nothing here requires reflashing unless it says
so. 

## 1. Runtime options (CMOS) — change without reflashing

coreboot exposes a set of options in CMOS/RTC NVRAM. They're editable from a
booted Linux with `nvramtool`, and they take effect on the next boot. **No
reflash, no programmer, no risk.**

```bash
sudo apt install nvramtool     # or build from coreboot's util/nvramtool
sudo nvramtool -a              # show every option and its current value
sudo nvramtool -e hybrid_graphics_mode   # show valid values for one option
sudo nvramtool -w hybrid_graphics_mode="Discrete Only"
```

| Option | Values | Default we ship | What it does |
|---|---|---|---|
| `hybrid_graphics_mode` | `Integrated Only`, `Discrete Only` | **Integrated Only** | Which GPU drives the panel. See §2. |
| `me_state` | `Normal`, `Disabled` | `Normal` | Runtime ME disable via HECI. Worth setting to `Disabled`. |
| `hyper_threading` | `Enable`, `Disable` | `Enable` | **Disables SMT in firmware.** See §3. |
| `gfx_uma_size` | `32M`–`224M` | `32M` | Memory stolen for the iGPU. |
| `debug_level` | `Emergency`…`Spew` | `Debug` | coreboot console verbosity. |
| `power_on_after_fail` | `Disable`, `Enable`, `Keep` | — | Behaviour after power loss. |
| `boot_option` | `Fallback`, `Normal` | `Normal` | Which CBFS image to boot. |
| `nmi` | `Enable`, `Disable` | — | NMI generation. |

Defaults live in `board/cmos.default`; the full option layout is
`board/cmos.layout`. Changing those two files *does* require a reflash — the
point of `nvramtool` is that you usually don't have to.

## 2. Switching between the integrated and discrete GPU

**This is not baked into the firmware.** It's the `hybrid_graphics_mode` CMOS
option above:

```bash
sudo nvramtool -w hybrid_graphics_mode="Discrete Only"    # then reboot
```

With `Integrated Only` (our default), coreboot's `early_hybrid_graphics()`
clears `DEVEN_PEG10`, so the NVIDIA GT 650M is **never enumerated at all** —
it doesn't appear in `lspci`, draws no power, and needs no video blob.

We chose integrated-only for four reasons, all still reversible:

1. No proprietary NVIDIA option ROM in the image.
2. 2011–2012 MacBook Pro dGPUs are notorious for failing. iGPU-only means the
   machine still boots if yours dies.
3. Power and heat in a 2012 chassis.
4. One fewer PCIe device initialised.

The 10,1 port supports the discrete GPU fine, so `Discrete Only` should work —
it just needs the NVIDIA option ROM added to CBFS to initialise properly.

## 3. Hardening knobs this firmware gives you

Things that are currently kernel-command-line workarounds become *firmware*
settings, which is strictly stronger — they apply before the OS loads and
can't be undone by editing GRUB:

- **`hyper_threading=Disable`** does in firmware what `nosmt=force` does in
  your cmdline. The cores are never brought up at all.
- **`me_state=Disabled`** stacks on top of the `AltMeDisable` descriptor bit
  and the me_cleaner'd region you already have.
- **`BOOTMEDIA_LOCK_WHOLE_RO` / `BOOTMEDIA_LOCK_CONTROLLER`** (build-time)
  lock the SPI controller at end-of-POST, on top of your descriptor lockdown.
- Thunderbolt and FireWire are simply never powered — no DMA path to attack.
  These are `devicetree.cb` settings, so changing them needs a rebuild.

## 4. Things that change after flashing

- **`/sys/firmware/efi` disappears.** You're no longer UEFI-booted.
  `efi=disable_early_pci_dma` in your cmdline becomes a no-op, and
  `grub-install` will need different arguments.
- **The EFI firmware password is gone** — it lived in Apple's NVRAM inside the
  BIOS region we're replacing. Restoring `vendor/orig.bin` brings it back, so
  don't forget it.
- **`apple_gmux` still matters.** It owns the backlight
  (`/sys/class/backlight/gmux_backlight`) — i915 skips its own backlight
  registration on this machine. It is currently **hard-blocked** on your
  system (`install apple_gmux /bin/true` in `blacklist-one.conf`); you'll want
  that lifted or the backlight won't be controllable.
- **Boot is much faster** and there's no Apple chime.

## 5. Rebuild and reflash workflow

```bash
cd <your coreboot tree>   # e.g. one built by scripts/setup-tree.sh
make                      # produces build/coreboot.rom (8 MiB, ready to flash)
```

Then flash `build/coreboot.rom` externally with the SOIC-8 clip — internal
flashing is impossible on this machine by design (`FLMSTR1` denies the host
CPU write access to every region).

Before each flash, sanity-check the image:

```bash
ifdtool -d build/coreboot.rom | head -30      # layout should match vendor/orig.bin
ls -l build/coreboot.rom                      # must be exactly 8388608 bytes
```

## 6. Debugging a board that won't boot

Symptoms map to boot stages fairly cleanly:

| Symptom | Stage | Suspect |
|---|---|---|
| No power, no fan | bootblock | `gpio.c` |
| Fans spin, nothing else | romstage | raminit — `spd_addresses`, `DRAM_RESET_GATE_GPIO` |
| Reaches ramstage, black screen | ramstage | libgfxinit / LVDS dual-channel |
| Boots, no audio | ramstage | `hda_verb.c` |

**usbdebug is the tool that distinguishes the first two**, and they are
otherwise indistinguishable from outside the case. `CONFIG_USBDEBUG_HCD_INDEX=0`;
on the 10,1 that's the right-hand USB port. Get a debug dongle working *before*
the first flash, not after.

Note this unit has **no internal speakers and no microphone** (removed), so
audio can only be tested through the headphone jack.

---

## When the GRUB password is asked for

The password prompt does **not** appear when the menu is displayed. GRUB's
`superusers` model demands credentials at the moment you attempt a protected
action -- booting an entry, pressing `e` to edit one, or `c` for a command
line. The menu itself is treated as public information.

So the sequence is: menu appears -> select an entry -> press Enter ->
*then* username and password -> boot. This is correct GRUB behaviour, not a
misconfiguration.

### The timeout does not bypass it

`set default=0` with `set timeout=5`, and no entry marked `--unrestricted`,
means that when the timeout expires GRUB attempts to boot entry 0, finds it
restricted, and stops at the password prompt. **The machine never auto-boots
unattended.** To confirm: sit at the menu and touch nothing for five seconds.

If you ever want unattended boot back (a headless reboot, say), add
`--unrestricted` to one menuentry -- that entry then boots without a password
while `e` and `c` stay protected. It is a real reduction in protection: anyone
who can power-cycle the machine can boot that entry.

Verified in `coreboot-hardened-spilock-LOCKED.rom`: `set superusers` and
`password_pbkdf2` on lines 41-42, all 8 menuentries after them, zero
`--unrestricted`.
