/* SPDX-License-Identifier: GPL-2.0-only */

#include <device/azalia_device.h>

/*
 * Cirrus Logic CS4206, codec address 0.
 *
 * Dumped from this board running the vendor firmware (Apple EFI 233.0.0.0.0)
 * via /proc/asound/card1/codec#0 on 2026-08-28. Raw dump preserved in the
 * project notes as cs4206-codec.txt.
 *
 * The subsystem ID (0x106b5300) and four pin configs differ from the
 * MacBookPro10,1: this board has a line-in jack (0x0c), an internal mic on
 * 0x0d rather than 0x0e, and an SPDIF input (0x0f), none of which the Retina
 * has.
 *
 * Note this uses the flat cim_verb_data[] form that current coreboot expects.
 * The MacBookPro10,1 CL (32673 patchset 67) uses a `struct azalia_codec
 * mainboard_azalia_codecs[]`, which does not exist anywhere in the tree --
 * that is one of several ways the CL no longer builds against main.
 *
 * The codec also drives two GPIOs under the vendor firmware:
 *   IO[1] enable=1 dir=out data=1
 *   IO[3] enable=1 dir=out data=1
 * i.e. mask/dir/data = 0x0a. Deliberately NOT set here, matching the 10,1:
 * Linux's snd_hda_codec_cs420x programs them itself. If speakers are silent
 * under a payload that does not run that driver, add:
 *	0x0017160a,	// SET_GPIO_MASK      0x0a
 *	0x0017170a,	// SET_GPIO_DIRECTION 0x0a
 *	0x0017150a,	// SET_GPIO_DATA      0x0a
 */
const u32 cim_verb_data[] = {
	0x10134206,	/* Codec Vendor / Device ID: Cirrus Logic CS4206 */
	0x106b5300,	/* Subsystem ID */
	11,		/* Number of 4 dword sets */

	AZALIA_SUBVENDOR(0, 0x106b5300),
	AZALIA_PIN_CFG(0, 0x09, 0x002b4050),	/* HP out, ext, green, combo */
	AZALIA_PIN_CFG(0, 0x0a, 0x90100141),	/* speaker, internal, fixed */
	AZALIA_PIN_CFG(0, 0x0b, 0x90100140),	/* speaker, internal, fixed */
	AZALIA_PIN_CFG(0, 0x0c, 0x008b3020),	/* line in, ext */
	AZALIA_PIN_CFG(0, 0x0d, 0x90a00110),	/* mic, internal, fixed */
	AZALIA_PIN_CFG(0, 0x0e, 0x400000f0),	/* unused */
	AZALIA_PIN_CFG(0, 0x0f, 0x00cbe030),	/* SPDIF in, ext, combo */
	AZALIA_PIN_CFG(0, 0x10, 0x004be060),	/* SPDIF out, ext, combo */
	AZALIA_PIN_CFG(0, 0x12, 0x400000f0),	/* unused */
	AZALIA_PIN_CFG(0, 0x15, 0x400000f0),	/* unused */
};

const u32 pc_beep_verbs[0] = {};

AZALIA_ARRAY_SIZES;
