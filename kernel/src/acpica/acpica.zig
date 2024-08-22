const std = @import("std");
const panic = @import("../common.zig").panic;
const console = @import("../console.zig");
const acpica = @cImport({
    @cDefine("_GNU_EFI", {});
    @cDefine("ACPI_USE_LOCAL_CACHE", {});
    @cInclude("acpi.h");
});

pub export var rsdp_addr: usize = 0;

const bios_start: [*]u8 = @ptrFromInt(0xe0000);
const bios_end: usize = 0xfffff;

pub fn findRsdp() void {
    var i: [*]u8 = bios_start;
    while (@intFromPtr(i) <= bios_end) : (i += 0x10) {
        if (std.mem.eql(u8, "RSD PTR ", i[0..8])) {
            rsdp_addr = @intFromPtr(i);
            break;
        }
    }
}

pub fn initializeAcpica() void {
    var status: acpica.ACPI_STATUS = 0;

    status = acpica.AcpiInitializeSubsystem();
    if (status != acpica.AE_OK) {
        panic("Unable to init acpica");
    }

    status = acpica.AcpiInitializeTables(null, 16, 0);
    if (status != acpica.AE_OK) {
        panic("Unable to init acpica");
    }

    status = acpica.AcpiLoadTables();
    if (status != acpica.AE_OK) {
        panic("Unable to init acpica");
    }

    status = acpica.AcpiEnableSubsystem(acpica.ACPI_FULL_INITIALIZATION);
    if (status != acpica.AE_OK) {
        panic("Unable to init acpica");
    }

    status = acpica.AcpiInitializeObjects(acpica.ACPI_FULL_INITIALIZATION);
    if (status != acpica.AE_OK) {
        panic("Unable to init acpica");
    }
}

pub fn parseAcpiData() void {}
