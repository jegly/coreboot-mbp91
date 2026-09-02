# Getting this upstream

Everything you need to submit this work to coreboot, written to be usable on a
machine that has never seen this project. Assumes only that you have this
folder and a working internet connection.

Base commit all of this was developed against:

```
coreboot 9ba5cc363a2a11f39df69947cea3f01139acdf78  (2026-08-07)
"mb/apple: Add MacBook Pro 10,1 (A1398) support"
```

---

## The awkward bit first: this spans three repositories

coreboot vendors libgfxinit and vboot as submodules. They have their own
repos, their own maintainers and their own review queues. Our changes land in
all three, and some of them depend on each other.

| # | Patch file | Repo | What it is |
|---|---|---|---|
| A | `0005-libgfxinit-ironlake-honour-ignore-presence-straps.patch` | **libgfxinit** | bug fix |
| B | `0001-libgfxinit-configurable-lvds-dual-threshold.patch` | **libgfxinit** | feature |
| C | `0003-vboot-const-strchr-gcc-strictness.patch` | **vboot** | build fix |
| D | `0006-apple-hybrid-graphics-dispatch-gmux-access.patch` | coreboot | bug fix |
| E | `0002-coreboot-gma-kconfig-lvds-dual-threshold.patch` | coreboot | needs B first |
| F | `0004-lvds-panel-mode-fallback-no-edid.patch` | coreboot | expect pushback |
| G | `board/` (the whole directory) | coreboot | the mainboard |

`0007-DEBUG-ONLY-lightup-ok-printk.patch` is **not for upstream**. It is a
debug printk kept only so the local tree can be reproduced exactly.

`0008-grub-usb-keyboard-discard-invalid-0xff-keycodes.patch` goes to **GNU
GRUB**, which is a fourth project with a completely different process. See the
section at the end.

### Submit in this order

Do not push all seven at once. Order matters, both technically and tactically.

1. **D** (gmux dispatch fix) - coreboot, standalone, small, clearly a bug
2. **A** (presence straps) - libgfxinit, standalone, small, clearly a bug
3. **B** (dual-link threshold) - libgfxinit
4. **E** (the Kconfig for B) - coreboot, only after B has landed and the
   submodule pointer has been bumped
5. **C** (vboot) - independent, submit whenever, see the caveat below
6. **F** (panel mode fallback) - expect to rework this
7. **G** (the mainboard) - biggest review, do it last

D and A are the ones to lead with. They fix real bugs affecting hardware
beyond this laptop, they are a few lines each, and landing them gives you a
track record before anyone has to review an entire new mainboard.

---

## Setting up on a fresh machine

### 1. Account

There is no coreboot-specific signup. Log in at
<https://review.coreboot.org> using **GitHub OAuth, Google OAuth, or an
OpenID provider**.

Use an address you will keep reading. Review threads on a new mainboard run
for weeks or months and everything arrives by email. A disposable address
loses you the thread and the account.

Pseudonyms are fine. coreboot's rule is "a known identity ... your name or an
established alias/nickname". Only fully anonymous contributions are refused.
Whatever you pick becomes permanent public record in the git history, so pick
once and stick to it.

### 2. SSH key

Generate one if this machine does not have one:

```bash
ssh-keygen -t ed25519 -C "your-gerrit-email"
```

Paste `~/.ssh/id_ed25519.pub` into
<https://review.coreboot.org/settings/#SSHKeys>. Test it:

```bash
ssh -p 29418 YOURUSER@review.coreboot.org
```

You should get a greeting, not a shell. That is correct.

### 3. Clone and hook

```bash
git clone ssh://YOURUSER@review.coreboot.org:29418/coreboot
cd coreboot
```

The commit-msg hook adds the `Change-Id` line Gerrit uses to track revisions
of a change across pushes. **Without it your push is rejected.**

```bash
curl -Lo .git/hooks/commit-msg https://review.coreboot.org/tools/hooks/commit-msg
chmod +x .git/hooks/commit-msg
```

Repeat that inside each submodule clone you work in.

### 4. Identity

This is what ends up in `Signed-off-by`, and it must match your Gerrit
account's registered email or the push is rejected.

```bash
git config user.name "your name or alias"
git config user.email "your-gerrit-email"
```

---

## Committing

Every commit needs a `Signed-off-by` line. `git commit -s` adds it from your
git config. The Developer Certificate of Origin you are signing says, in
short, that you wrote the change or have the right to submit it, and that you
understand it becomes permanent public record.

coreboot's commit message style:

```
area/subarea: Short imperative summary under ~65 chars

Body explaining what was wrong and why this fixes it. Wrap at 72
columns. Describe the problem before the solution. Mention how it was
tested and on what hardware.

TEST=Describe what you did to verify this.

Signed-off-by: Your Name <your@email>
```

Do not write `Change-Id` yourself. The hook does it.

---

## The changes, one at a time

### D. gmux dispatch fix (coreboot, do this first)

```bash
cd coreboot
git checkout -b gmux-dispatch origin/main
patch -p1 < /path/to/mbp91-coreboot/patches/0006-apple-hybrid-graphics-dispatch-gmux-access.patch
git add src/drivers/apple/hybrid_graphics/
git commit -s
```

Suggested message:

```
drivers/apple/hybrid_graphics: Honour the board's gmux_indexed setting

hybrid_graphics.c called gmux_index_read32() directly, hardcoding the
indexed gmux protocol and ignoring the mainboard's own "gmux_indexed"
devicetree setting. On any Apple board with a classic (port I/O) gmux
every read returns zero, so the driver saw version 0.0.0 and a maximum
brightness of 0, and gmux_switch() never moved the display mux.

Add gmux_pio_write32() and a dispatching gmux_read32()/gmux_write32()
pair that select the access method from the devicetree, and use those
throughout.

Found on an Apple MacBookPro9,1, which has a classic gmux. Linux reports
it as:

  apple_gmux: Found gmux version 1.9.35 [classic]

Inheriting gmux_indexed=1 from the MacBookPro10,1 (which is genuinely
indexed) left the panel wired to a powered-off discrete GPU while
libgfxinit programmed the integrated one correctly, producing a black
screen with no error output.

TEST=Booted MacBookPro9,1 with gmux_indexed=0; coreboot now reads the
correct gmux version and brightness, and the internal panel lights.

Signed-off-by: ...
```

```bash
git push origin HEAD:refs/for/main
```

### A. libgfxinit presence straps (bug fix)

libgfxinit is its own repo:

```bash
git clone ssh://YOURUSER@review.coreboot.org:29418/libgfxinit
cd libgfxinit
curl -Lo .git/hooks/commit-msg https://review.coreboot.org/tools/hooks/commit-msg
chmod +x .git/hooks/commit-msg
git checkout -b ironlake-presence-straps origin/master
patch -p1 < /path/to/mbp91-coreboot/patches/0005-libgfxinit-ironlake-honour-ignore-presence-straps.patch
git commit -s -a
git push origin HEAD:refs/for/master
```

Note the branch is `master`, not `main`. Check with `git branch -r` before
pushing.

Suggested message:

```
ironlake: Honour Config.Ignore_Presence_Straps

GFX_GMA_IGNORE_PRESENCE_STRAPS is documented as a generic option, but
Config.Ignore_Presence_Straps was only ever read by
haswell_shared/hw-gfx-gma-port_detect.adb. On Ironlake through Ivy
Bridge the option compiled fine and silently did nothing.

Apple's MacBookPro9,1 needs it: its LVDS presence strap does not read as
set at cold boot, so Valid_Port (LVDS) stayed False and
Config_Helpers.Fill_Port_Config then declined to program the port, with
no console output to say why.

TEST=With GFX_GMA_IGNORE_PRESENCE_STRAPS selected on MacBookPro9,1, the
LVDS port is now probed and the internal panel lights.

Signed-off-by: ...
```

### B. libgfxinit dual-link threshold

Same repo, separate change:

```bash
git checkout -b lvds-dual-threshold origin/master
patch -p1 < /path/to/mbp91-coreboot/patches/0001-libgfxinit-configurable-lvds-dual-threshold.patch
git commit -s -a
git push origin HEAD:refs/for/master
```

The argument to make in the message: libgfxinit picks single vs dual channel
LVDS purely from pixel clock against a hardcoded 95 MHz threshold. Panels
exist that are wired dual-channel but run below it, and they stay dark. Linux
solves the same problem with a per-machine DMI quirk
(`intel_dual_link_lvds`). This board needs 88.75 MHz.

### E. coreboot Kconfig for the threshold

**Only after B has landed.** It adds the Kconfig that drives the value B
introduced, so it is meaningless until then, and coreboot's submodule pointer
for libgfxinit has to be bumped to a commit containing B.

Mention the dependency explicitly in the commit message and add a
`Depends-on:` line with B's Change-Id.

### C. vboot const/strchr fix

**Check where this belongs before pushing.** coreboot's `3rdparty/vboot`
mirrors Chromium's `platform/vboot_reference`, and fixes are often expected
on Chromium's Gerrit rather than coreboot's. Ask on IRC or the mailing list
first; it is a one-line change and not worth pushing to the wrong place.

The change itself: `host/lib/cbfstool.c` assigns the result of `strchr()` on a
const pointer to a non-const one, which newer GCC rejects.

### F. Panel mode fallback

Expect pushback on this one, and go in expecting to rework it.

It hardcodes a specific panel's timings into
`src/drivers/intel/gma/text_fb/gma-gfx_init.adb`, which is generic code. A
reviewer will reasonably ask why a board-specific mode is in a shared driver.

Likely outcomes:

* asked to move it into the mainboard, via `gma-mainboard.ads` or a devicetree
  property
* asked to make it a generic "fallback mode when no EDID" mechanism that any
  board can populate
* asked to drop it and supply the EDID some other way

Any of those is fine. The underlying problem is real: `Probe_Port` derives the
mode only from EDID and has no fallback at all, so a panel with no EDID cannot
work. Lead with that framing rather than with our specific fix.

Note this only patches the `text_fb` variant. A `hires_fb` build needs the
same treatment, which is worth mentioning up front.

### G. The mainboard

Last, and the longest review. Copy `board/` in as
`src/mainboard/apple/macbookpro9_1/`.

Before pushing, check the things CI will check:

```bash
util/lint/lint-stable
```

and make sure `board_info.txt` is filled in properly. It needs at minimum
vendor, board name, category, ROM package, ROM protocol, ROM socketed, flashrom
support, release year.

Things reviewers will very likely raise:

* **`DRAM_RESET_GATE_GPIO = 28`** was inherited from the MacBookPro10,1. It is
  now **validated**: S3 suspend and resume works on this board, which exercises
  exactly that path. Say so in the commit message, because a reviewer will ask
  where the value came from. The paragraph below is kept for context on how it
  was originally derived.

* (historical) `DRAM_RESET_GATE_GPIO = 28` is inherited from the 10,1 and has
  never been verified on this board. Say so in the commit message rather than
  letting someone find it. S3 resume exercises it, and S3 now works on this board.
* Documentation. New mainboards are generally expected to add a page under
  `Documentation/mainboard/`. Much of `github/README.md` can be adapted.
* The five build fixes from the 10,1 CL (see `BUILDS.md`) are folded into
  `board/` already, so the board builds standalone. Good, but be ready to
  explain the relationship to CL 32673 since a reviewer will recognise it.

Credit CL 32673 in the commit message. This port is derived from it and that
should be visible.

---

## After you push

Gerrit prints a URL. That is your change. What happens next:

* **Jenkins builds it automatically.** A red build is almost always a lint
  error or a missing `Signed-off-by`, not a real failure.
* **To update a change**, amend and push to the same target. The `Change-Id`
  keeps it attached as a new patchset, rather than creating a duplicate.

  ```bash
  git commit --amend
  git push origin HEAD:refs/for/main
  ```

  Never remove or edit the `Change-Id` line.
* **Reviews are slow.** Weeks is normal, months for a mainboard. Silence is
  not rejection; it is a small volunteer project.
* If a change sits untouched, `#coreboot` on libera.chat is the place to
  politely nudge.

---

## H. The GRUB patch (0008) - a completely different process

GNU GRUB does not use Gerrit. Patches go to a mailing list, and **you must be
subscribed to post**:

* List: `grub-devel@gnu.org`
* Subscribe: <https://lists.gnu.org/mailman/listinfo/grub-devel>
* Archive: <https://lists.gnu.org/archive/html/grub-devel/>

### Copyright

For large contributions GRUB requires an FSF copyright assignment, which takes
weeks of paperwork. **This patch is six lines**, which is comfortably in
trivial territory and should not trigger it. Add a `Signed-off-by` line
anyway. If a maintainer does ask for assignment, that is the process working
rather than a rejection.

### Sending it

```bash
cd <grub tree>
git checkout -b usb-keyboard-0xff grub-2.12
git apply /path/to/mbp91-coreboot/patches/0008-grub-usb-keyboard-discard-invalid-0xff-keycodes.patch
git commit -s -a
git send-email --to=grub-devel@gnu.org --subject-prefix=PATCH HEAD~1
```

If `git send-email` is not set up, `git format-patch -1` and paste the file
into a plain-text mail. HTML mail gets silently ignored on GNU lists.

### The argument to make

Lead with the asymmetry, because it is the whole case and it is checkable in
thirty seconds:

* `grub-core/term/ps2.c` already discards `0xff`, with the comment *"May
  happen if no keyboard is connected. Just ignore this."*
* `grub-core/term/usb_keyboard.c` filters the HID error codes
  (`KEY_ERR_BUFFER`, `KEY_ERR_POST`, `KEY_ERR_UNDEF`) but **not** `0xff`,
  which is not a valid HID keyboard usage either.

Suggested message:

```
usb_keyboard: Discard invalid 0xff keycodes

usb_keyboard.c filters the HID error codes KEY_ERR_BUFFER, KEY_ERR_POST
and KEY_ERR_UNDEF, but passes 0xff through to grub_term_map_key(). 0xff
is not a valid HID keyboard usage, and map_key_core() cannot map it, so
each one produces an unconditional

  Unknown key 0xff detected

from grub-core/commands/keylayouts.c:177.

On a machine whose keyboard is itself a USB device, plugging in a USB
mass storage device disrupts the keyboard's interrupt transfers long
enough that reports come back as 0xff. The menu is then flooded with
that message continuously. Navigation still works, but the display is
unusable.

ps2.c already discards the equivalent case:

  /* May happen if no keyboard is connected. Just ignore this.  */
  if (at_key == 0xff)
    return -1;

Treat 0xff the same way in usb_keyboard.c.

TEST=Apple MacBookPro9,1 running coreboot with the GRUB payload. With a
USB stick inserted at power-on the menu was previously flooded with
"unknown key 0xff detected"; with this patch the menu is clean and the
stick still enumerates normally.

Signed-off-by: ...
```

Expect this to be slower than Gerrit. Mailing list patches can sit for a
while, and a polite ping after a few weeks is normal and welcome.

---

## What must survive the wipe

Everything needed lives in this folder. Specifically:

* `patches/` - all seven patches. **0001 through 0006 are the upstreamable
  work.** 0007 is debug only.
* `board/` - the mainboard, synced from the tree that built the working ROM.
  Verified to contain `gmux_indexed = "0"` and
  `select GFX_GMA_IGNORE_PRESENCE_STRAPS`. An earlier copy of this directory
  had neither and would not have booted.
* `BUILDS.md` - what each ROM is and how it was built.
* `vendor/` - your own descriptor and ME. **Never push these anywhere.**
* `coreboot-tree/` - a full copy of the working tree, roughly 1.5 GB. If you
  keep it you can reconstruct exactly; if not, `scripts/setup-tree.sh` rebuilds
  from upstream plus `patches/`.
* `github/` - the sanitised public subset, ready to publish. Contains no ROMs,
  no blobs, no serial number.

Check before wiping:

```bash
grep -c 'gmux_indexed" = "0"' board/devicetree.cb   # must be 1
grep -c IGNORE_PRESENCE_STRAPS board/Kconfig        # must be 1
ls patches/*.patch | wc -l                          # must be 8
```
