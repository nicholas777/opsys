const std = @import("std");

const panic = @import("../common.zig").panic;
const mem = @import("../arch/i386/memory.zig");
const aml = @import("aml.zig");

fn memcmp(ptr1: [*]u8, ptr2: [*]u8, size: usize) bool {
    var i: usize = 0;
    while (i < size) : (i += 1) {
        if (ptr1[i] != ptr2[i]) return false;
    }

    return true;
}

pub const RSDP = packed struct {
    sig: u64,
    checksum: u8,
    oem_id: u48,
    revision: u8,
    rsdt_addr: *TableHeader,
};

const SigRSDT = "RSDT";
const SigXSDT = "XSDT";
const SigFADT = "FACP";
const SigMADT = "APIC";
const SigSSDT = "SSDT";

pub const TableHeader = packed struct {
    sig: u32,
    length: u32, // Includes the header
    revision: u8,
    checksum: u8,
    oem_id: u48,
    oem_table_id: u64,
    oem_revision: u32,
    creator_id: u32,
    creator_revision: u32,
};

pub const ACPIInfo = struct {
    version: std.SemanticVersion,
    rsdt: ?*TableHeader = null,
    fadt: ?*TableHeader = null,
    madt: ?*TableHeader = null,
    ssdt: ?*TableHeader = null,
    dsdt: ?*TableHeader = null,
};

pub fn checkSum(header: *TableHeader) bool {
    var sum: usize = 0;
    for (@as([*]u8, @ptrCast((header)))[0..header.length]) |byte| {
        sum += byte;
    }

    return (sum & 0xFF) == 0;
}

const bios_start: [*]u8 = @ptrFromInt(0xE0000);
const bios_end: [*]u8 = @ptrFromInt(0xFFFFF);

const rsdp_sig = "RSD PTR ";

// See: https://wiki.osdev.org/RSDP
pub fn findRsdp() error{RsdpNotFound}!*RSDP {
    var ptr: [*]u8 = bios_start;
    while (@intFromPtr(ptr) < @intFromPtr(bios_end)) : (ptr += 16) {
        if (memcmp(ptr, @ptrCast(@constCast(rsdp_sig.ptr)), rsdp_sig.len) == true)
            return @ptrCast(@alignCast(ptr));
    }

    return error.RsdpNotFound;
}

fn getSignature(table: *TableHeader) []const u8 {
    return std.mem.asBytes(table)[0..4];
}

pub fn getRsdt() *TableHeader {
    const rsdp = findRsdp() catch panic("RSDP not found");
    if (rsdp.revision != 0) {
        panic("We currently only support ACPI version 1.x");
    }

    var sum: usize = 0;
    for (std.mem.asBytes(rsdp)) |byte| {
        sum += byte;
    }

    if (sum & 0xFF != 0) {
        panic("Invalid checksum in RSDP");
    }

    if (checkSum(rsdp.rsdt_addr) == false) {
        panic("Invalid checksum in RSDT");
    }

    return rsdp.rsdt_addr;
}

fn mapTable(table: *TableHeader) *TableHeader {
    const table_int = @intFromPtr(table);
    return @as(*TableHeader, @ptrFromInt(mem.mapPageAt(
        .KernelRO,
        table_int - (table_int % mem.PAGE_SIZE),
    ) + table_int % mem.PAGE_SIZE));
}

fn unmapTable(table: *TableHeader) void {
    const table_int = @intFromPtr(table);
    mem.freePage(table_int - (table_int % mem.PAGE_SIZE), true);
}

const console = @import("../console.zig");

pub fn mapAndParseACPI(alloc: std.mem.Allocator, rsdt_physical: *TableHeader) *ACPIInfo {
    var info = alloc.create(ACPIInfo) catch unreachable;

    const rsdt = mapTable(rsdt_physical);
    info.rsdt = rsdt;

    // TODO: Make sure that no tables are mapped twice
    // Map and save the tables we need
    const rsdt_len = (rsdt.length - @sizeOf(TableHeader)) / 4;
    var rsdt_entries: [*]u32 = @ptrFromInt(@intFromPtr(rsdt) + @sizeOf(TableHeader));
    for (rsdt_entries[0..rsdt_len]) |ptr| {
        const table = mapTable(@ptrFromInt(ptr));
        if (std.mem.eql(u8, getSignature(table), SigFADT)) {
            info.fadt = table;
        } else if (std.mem.eql(u8, getSignature(table), SigMADT)) {
            info.madt = table;
        } else if (std.mem.eql(u8, getSignature(table), SigSSDT)) {
            info.ssdt = table;
        } else {
            unmapTable(table);
        }
    }

    if (info.fadt == null) panic("No ACPI FADT table present");
    if (checkSum(info.fadt.?) == false) panic("Invalid ACPI FADT table");

    const ver_min = @as([*]u8, @ptrCast(info.fadt.?))[131];
    info.version = .{
        .major = info.fadt.?.revision,
        .minor = ver_min & 0xF,
        .patch = ver_min >> 4,
    };
    console.printf("{}.{} errata {c}\n", .{
        info.version.major,
        info.version.minor,
        'A' + @as(u8, @intCast(info.version.patch)) - 1,
    });

    const dsdt_int = @intFromPtr(info.fadt.?) + @sizeOf(TableHeader);
    info.dsdt = @ptrFromInt(@as([*]u32, @ptrFromInt(dsdt_int))[1]);
    const dsdt_page: usize = @intFromPtr(info.dsdt.?) - (@intFromPtr(info.dsdt.?) % mem.PAGE_SIZE);

    info.dsdt = mapTable(info.dsdt.?);

    var i: usize = mem.PAGE_SIZE;
    while (i < info.dsdt.?.length) : (i += mem.PAGE_SIZE) {
        _ = mem.mapPageAt(.KernelRO, dsdt_page + i);
    }

    if (checkSum(info.dsdt.?) == false) panic("Invalid ACPI DSDT table");

    _ = aml.parseDSDT(alloc, info.dsdt.?) catch panic("Unable to parse ACPI DIST");

    return info;
}
