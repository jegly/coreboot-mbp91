/* SPDX-License-Identifier: GPL-2.0-only */

#include <acpi/acpi.h>
DefinitionBlock(
	"dsdt.aml",
	"DSDT",
	ACPI_DSDT_REV_2,
	OEM_ID,
	ACPI_TABLE_CREATOR,
	/*
	 * A literal OEM revision, as every other in-tree board uses. The
	 * MacBookPro10,1 CL (32673 patchset 67) has COREBOOT_OEM_REVISION
	 * here, but that macro no longer exists anywhere in coreboot -- the
	 * change was rebased onto main without updating this reference, so
	 * the CL does not currently build. iasl fails with
	 * "syntax error and premature End-Of-File" at dsdt.asl line 7,
	 * because the identifier is left unexpanded by the preprocessor.
	 */
	0x20260828
)
{
	#include <acpi/dsdt_top.asl>
	#include "acpi/platform.asl"
	#include <cpu/intel/common/acpi/cpu.asl>
	#include <southbridge/intel/common/acpi/platform.asl>
	#include <southbridge/intel/bd82x6x/acpi/globalnvs.asl>
	#include <southbridge/intel/common/acpi/sleepstates.asl>

	Device (\_SB.PCI0)
	{
		#include <northbridge/intel/sandybridge/acpi/sandybridge.asl>
		#include <drivers/intel/gma/acpi/default_brightness_levels.asl>
		#include <southbridge/intel/bd82x6x/acpi/pch.asl>
	}
}
