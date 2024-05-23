const std = @import("std");

fn memcmp(ptr1: [*]u8, ptr2: [*]u8, size: usize) bool {
    var i: usize = 0;
    while (i < size) : (i += 1) {
        if (ptr1[i] != ptr2[i]) return false;
    }

    return true;
}

const bios_start: [*]u8 = @intFromPtr(0xE0000);
const bios_end: [*]u8 = @intFromPtr(0xFFFFF);

const rsdp_sig: []u8 = "RSD PTR ";

// See: https://wiki.osdev.org/RSDP

/// Needs to be called before paging is enabled
pub fn findRsdp() error{RsdpNotFound}![*]u8 {
    var ptr: [*]u8 = bios_start;
    while (ptr < bios_end) : (ptr += 16) {
        if (memcmp(ptr, rsdp_sig.ptr, rsdp_sig.len) == true)
            return ptr;
    }

    return error.RsdpNotFound;
}
