/* SPDX-License-Identifier: GPL-2.0-only */

#include <device/pci_ops.h>
#include <northbridge/intel/sandybridge/sandybridge.h>
#include <northbridge/intel/sandybridge/raminit.h>
#include <southbridge/intel/bd82x6x/pch.h>
#include <drivers/apple/hybrid_graphics/hybrid_graphics.h>

/*
 * Signature must match the declaration in
 * northbridge/intel/sandybridge/sandybridge.h, which takes an int. The
 * MacBookPro10,1 CL (32673 patchset 67) declares this as bool and no longer
 * compiles against current main.
 */
void mainboard_early_init(int s3resume)
{
	bool igd, peg;
	u32 reg32;

	early_hybrid_graphics(&igd, &peg);

	/* Hide disabled devices */
	reg32 = pci_read_config32(HOST_BRIDGE, DEVEN);
	reg32 &= ~(DEVEN_PEG10 | DEVEN_IGD);

	if (peg)
		reg32 |= DEVEN_PEG10;

	if (igd) {
		reg32 |= DEVEN_IGD;
	} else {
		/* Disable IGD VGA decode, no GTT or GFX stolen */
		pci_write_config16(HOST_BRIDGE, GGC, 2);
	}

	pci_write_config32(HOST_BRIDGE, DEVEN, reg32);
}

/*
 * Unlike the MacBookPro10,1, this machine has two ordinary DDR3 SO-DIMM
 * sockets, so the SPD EEPROMs are read over SMBus at runtime. There is no
 * board-ID GPIO vector to decode and no per-module SPD blob in CBFS, which
 * is why HAVE_SPD_IN_CBFS is not selected and spd/ does not exist.
 *
 * Note there is deliberately no mb_get_spd_map() here. mainboard_get_spd() in
 * northbridge/intel/sandybridge/raminit.c only calls it under
 * CONFIG(HAVE_SPD_IN_CBFS); on the other branch it reads cfg->spd_addresses
 * straight out of the devicetree. Defining it here would be dead code and
 * would falsely suggest the addresses live in this file. They are in
 * devicetree.cb -- see the "spd_addresses" register.
 */
