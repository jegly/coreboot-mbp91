/* SPDX-License-Identifier: GPL-2.0-only */

#define LIDS_OFFSET 0x60
#define HPAC_OFFSET 0x60
#define WKLD_OFFSET 0x68

#include <ec/apple/acpi/ec.asl>

/*
 * ac.asl defines the AC device and the HPAC field; lid.asl defines LID.
 * ec/apple/acpi/ec.asl references all three -- Notify(LID, 0x80),
 * Notify(AC, 0x80), and its included battery.asl reads HPAC -- so both
 * of these are mandatory, not optional extras.
 *
 * The MacBookPro10,1 CL (32673 patchset 67) drops these two includes and
 * puts gmux.asl in their place rather than alongside them, which is why
 * it fails to compile with three "Error 6084 - Object does not exist"
 * for LID_, AC__ and HPAC. Both upstream Apple boards that do build
 * (macbook21, macbookair4_2) include ec.asl + ac.asl + lid.asl.
 */
#include <ec/apple/acpi/ac.asl>
#include <ec/apple/acpi/lid.asl>

#include <drivers/apple/hybrid_graphics/acpi/gmux.asl>
