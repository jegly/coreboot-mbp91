#!/usr/bin/env bash
#
# Reapply the machine-specific tweaks this MacBookPro9,1 needs after a fresh
# Ubuntu install. None of these are coreboot-related -- the firmware keeps its
# own settings in the flash chip and survives any reinstall. These are all
# userspace defaults that happen to be wrong (or merely conservative) for this
# hardware.
#
# Safe to re-run. Run as your normal user, NOT as root -- the PipeWire parts
# write to ~/.config and must belong to your session user. Sudo is requested
# only for the steps that genuinely need it.
#
set -euo pipefail

[ "$EUID" -ne 0 ] || { echo "Run this as your normal user, not root." >&2; exit 1; }

echo "==> 1. Audio: allow native sample rates"
# PipeWire pins the device to 48000 Hz by default, so 44.1 kHz material (most
# music) is resampled. Ubuntu ships the fix but leaves it disabled. Enabling it
# lets PipeWire clock the hardware at the content's own rate instead.
# Trade-off: a brief gap when the rate switches. Harmless on this codec, which
# natively does 32/44.1/48/88.2/96/176.4/192 kHz.
mkdir -p ~/.config/pipewire/pipewire.conf.d
ln -sf /usr/share/pipewire/pipewire.conf.avail/10-rates.conf \
       ~/.config/pipewire/pipewire.conf.d/
echo "    enabled 10-rates.conf"

echo "==> 2. Audio: better resampler for when it IS needed"
mkdir -p ~/.config/client-rt.conf.d 2>/dev/null || true
mkdir -p ~/.config/pipewire/client-rt.conf.d
cat > ~/.config/pipewire/client-rt.conf.d/10-resample.conf <<'EOF'
stream.properties = {
    resample.quality = 10
}
EOF
echo "    resample.quality = 10 (default is 4, range 0-14)"

echo "==> 3. Audio: stop the codec powering down between sounds"
# The CS4206 pops and briefly mutes when it re-powers mid-stream. Symptoms are
# crackle, silence at the start of playback, and "sounds muted until I replug".
sudo tee /etc/modprobe.d/audio-nopowersave.conf >/dev/null <<'EOF'
options snd_hda_intel power_save=0 power_save_controller=N
EOF
# Apply now as well as at next boot.
echo 0 | sudo tee /sys/module/snd_hda_intel/parameters/power_save >/dev/null 2>&1 || true
echo "    power_save=0"

echo "==> 4. Keep the GRUB menu visible"
# Needed so the kernel command line can be edited at boot for one-off firmware
# audits (remove lockdown=confidentiality, add iomem=relaxed). With a GRUB
# password set, editing is already protected.
sudo tee /etc/default/grub.d/99-menu-visible.cfg >/dev/null <<'EOF'
GRUB_TIMEOUT=5
GRUB_TIMEOUT_STYLE=menu
EOF
sudo update-grub >/dev/null 2>&1 || sudo update-grub
echo "    99-menu-visible.cfg written"

echo "==> 5. Hardware video decode"
# Under Apple's EFI, i915 never bound (it waited forever on the blacklisted
# apple_gmux) and the machine ran on simple-framebuffer with no acceleration
# at all. Under coreboot the iGPU works properly, so VA-API is worth having.
if ! dpkg -s i965-va-driver >/dev/null 2>&1; then
	sudo apt-get install -y i965-va-driver
else
	echo "    already installed"
fi

echo "==> 6. Restart the audio stack"
systemctl --user restart wireplumber pipewire pipewire-pulse
echo

cat <<'EOF'
Done. Verify:

    # should show 44100 while 44.1 kHz material is playing, not always 48000
    cat /proc/asound/card0/pcm0p/sub0/hw_params

    # ERR column counts buffer underruns -- should stay at 0
    pw-top

    # firmware write protection (unchanged by any reinstall)
    sudo fwupdmgr security | grep SPI

NOT handled here, deliberately:

  - The LUKS/swap layout. Ubuntu's guided "encrypt the new installation" must
    leave /boot on its own unencrypted partition, or the coreboot GRUB payload
    cannot read your kernel -- it has no cryptodisk module. Check with:
        lsblk -o NAME,FSTYPE,MOUNTPOINT | grep -A1 boot
  - Encrypting swap (fwupdmgr flags it). Do this before ever using hibernate,
    or RAM contents get written to disk in plaintext.
  - The hardened kernel command line. slab_debug=FZP, init_on_free=1 and
    nosmt=force cost real latency headroom on a 2012 quad-core and are a
    plausible contributor to audio underruns. That is your call, not a default.
EOF
