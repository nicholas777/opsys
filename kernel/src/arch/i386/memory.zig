const std = @import("std");

const panic = @import("../../common.zig").panic;
const console = @import("../../console.zig");
const heap = @import("../../heap.zig");
const mb = @import("../../multiboot.zig");

const mmap_size = 1024 * 1024 / 8;

var physical_mmap: [mmap_size]u8 = undefined;

const PAGE_USED: u8 = 1;
const PAGE_FREE: u8 = 0;

pub const PAGE_SIZE = 4096;

pub fn allocPhysicalPage() usize {
    var i: usize = 0;
    while (i < physical_mmap.len) : (i += 1) {
        var j: u3 = 0;
        while (j < 8) : (j += 1) {
            if ((physical_mmap[i] >> j) & 0x1 == PAGE_FREE) {
                physical_mmap[i] |= (PAGE_USED << j);
                return (i * 8 + j) * PAGE_SIZE;
            }

            if (j == 7) break;
        }
    }

    return 0;
}

/// Check whether page is being used
pub fn checkPhysicalPage(addr: usize) bool {
    const index = (addr / PAGE_SIZE) / 8;
    const bit = (addr / PAGE_SIZE) & 8;

    return (physical_mmap[index] >> bit) & 0x1 == PAGE_USED;
}

pub fn freePhysicalPage(addr: usize) void {
    const index = (addr / PAGE_SIZE) / 8;
    const bit = (addr / PAGE_SIZE) & 8;

    physical_mmap[index] &= ~(PAGE_USED << @intCast(bit));
}

fn markPagesUsed(start: usize, end: usize) void {
    if ((@as(u64, start) + @as(u64, end)) / 8 >= mmap_size) return;

    const start_page = start / PAGE_SIZE;
    const end_page = if ((end / PAGE_SIZE) * PAGE_SIZE < end) end / PAGE_SIZE + 1 else end / PAGE_SIZE;

    const end_byte = end_page / 8;
    const end_bit = end_page % 8;

    var i: usize = start_page / 8;
    var j: usize = start_page % 8;

    while (i <= end_byte) : (i += 1) {
        var end_at: usize = 8;
        if (i == end_byte) {
            end_at = end_bit;
        }

        while (j < end_at) : (j += 1) {
            physical_mmap[i] |= (PAGE_USED << @intCast(j));
        }

        j = 0;
    }
}

fn markPageUsed(addr: usize) void {
    const pagenr = addr / PAGE_SIZE;
    const index = pagenr / 8;
    const bit = pagenr % 8;

    physical_mmap[index] |= PAGE_USED << @intCast(bit);
}

extern const kernel_start: usize;
extern const kernel_end: usize;

var page_directory: [1024]u32 align(4096) linksection(".bss") = undefined;
var pt_1023: [1024]u32 align(4096) linksection(".bss") = undefined;

fn present(entry: u32) bool {
    return entry & 0x1 == 1;
}

pub const PageTableType = enum(u8) {
    KernelRO = 0b00000001,
    KernelRW = 0b00000011,
    UserRO = 0b00000101,
    UserRW = 0b00000111,
};

const PAGE_FLAG: u32 = 0x3FF;

fn registerPT(i: usize, pt_type: PageTableType) usize {
    const addr = allocPhysicalPage();

    page_directory[i] = addr | @intFromEnum(pt_type);
    pt_1023[i] = addr | @intFromEnum(pt_type);

    return addr;
}

pub fn mapPage(pt_type: PageTableType) usize {
    return mapPageAt(pt_type, allocPhysicalPage());
}

pub export fn mapPageAt(pt_type: PageTableType, addr: usize) usize {
    var i: usize = 0;
    var j: usize = 0;

    while (i <= 1023) : (i += 1) {
        if (i == 1023) break;
        if (!present(page_directory[i])) break;

        const pt = @as([*]u32, @ptrFromInt((1023 << 22) | (i << 12)));
        while (j <= 1024) : (j += 1) {
            if (j == 1024) break;
            if (!present(pt[j])) {
                break;
            }
        }

        if (j != 1024) break;
        j = 0;
    }

    if (i == 1023) panic("Out of memory in page directory");

    var pt: [*]u32 = undefined;
    if (!present(page_directory[i])) {
        _ = registerPT(i, .KernelRW);
        pt = @as([*]u32, @ptrFromInt((1023 << 22) | (i << 12)));
    } else {
        pt = @as([*]u32, @ptrFromInt((1023 << 22) | (i << 12)));
    }

    pt[j] = addr | @intFromEnum(pt_type);

    markPageUsed(addr);
    reloadPT();
    return (i << 22) | (j << 12);
}

export fn mapPagesAt(pt_type: PageTableType, addr: usize, n: usize) usize {
    const ptr = mapPageAt(pt_type, addr);

    var i: usize = 1;
    while (i < n) : (i += 1) {
        _ = mapPageAt(pt_type, addr + i * 4096);
    }

    return ptr;
}

fn reloadPT() void {
    asm volatile (
        \\movl %cr3, %eax
        \\movl %eax, %cr3
        ::: "eax");
}

fn mapPageAtTo(pt_type: PageTableType, addr: usize, virtual: usize) usize {
    const pde = virtual >> 22;
    const pte = (virtual >> 12) & 0x3FF;

    var pt: [*]u32 = undefined;
    if (!present(page_directory[pde])) {
        pt = @as([*]u32, @ptrFromInt(registerPT(pde, .KernelRW)));
    } else {
        pt = @as([*]u32, @ptrFromInt(page_directory[pde] & (~PAGE_FLAG)));
    }

    pt[pte] = addr | @intFromEnum(pt_type);

    return addr;
}

pub export fn freePage(addr: usize, free_physical: bool) void {
    const pde = addr >> 22;
    const pte = (addr >> 12) & 0x3FF;

    const pt: [*]u32 = @ptrFromInt((1023 << 22) | (pde << 12));
    if (free_physical) freePhysicalPage(pt[pte] & ~(PAGE_FLAG));
    pt[pte] = 0;
}

pub fn initPaging(mmap: [*]mb.MemoryMap, mmap_len: u32) void {
    markPagesUsed(0, 0x16000); // Just ignore this part, bootloader and such reside here
    markPagesUsed(@intFromPtr(&kernel_start), @intFromPtr(&kernel_end));

    var map_entry: [*]mb.MemoryMap = mmap;
    var size: usize = 0;
    while (size < mmap_len) : (map_entry += 1) {
        const esize: u32 = @intCast(map_entry[0].length & 0xFFFFFFFF);
        const eaddr: u32 = @intCast(map_entry[0].addr & 0xFFFFFFFF);

        if (map_entry[0].type != mb.MemoryAvailable and
            map_entry[0].addr + map_entry[0].length <= std.math.maxInt(u32))
            markPagesUsed(eaddr, eaddr + esize);

        size += map_entry[0].size + 4; // The size field itself does not count towards .size
    }

    // The last page table is used to map the other page tables
    const pt_addr = @intFromPtr(&pt_1023);

    page_directory[1023] = pt_addr | @intFromEnum(PageTableType.KernelRW);
    pt_1023[1023] = pt_addr | @intFromEnum(PageTableType.KernelRW);

    // Now we just need to map the kernel itself
    const kstart_page = @intFromPtr(&kernel_start) / PAGE_SIZE;
    const kend_page = @intFromPtr(&kernel_end) / PAGE_SIZE + 1;

    var i: usize = kstart_page;
    while (i <= kend_page) : (i += 1) {
        const addr = i * PAGE_SIZE;
        _ = mapPageAtTo(.KernelRW, addr, addr);
    }

    _ = mapPageAtTo(.KernelRW, 0xB8000, 0xB8000);
    markPageUsed(0xB8000);

    // And the kernel heap
    const heap_addr = (kend_page + 1) * PAGE_SIZE;
    const heap_end = heap_addr + (1024 * PAGE_SIZE);
    markPagesUsed(heap_addr, heap_end);

    i = kend_page + 1;
    while (i <= heap_end / PAGE_SIZE) : (i += 1) {
        const addr = i * PAGE_SIZE;
        _ = mapPageAtTo(.KernelRW, addr, addr);
    }

    heap.addBlock(heap_addr, heap_end - heap_addr, 16);

    // Enable the paging
    asm volatile (
        \\ movl %[pd], %cr3
        \\ movl %cr0, %ebx
        \\ orl $0x80000001, %ebx
        \\ movl %ebx, %cr0
        :
        : [pd] "{eax}" (&page_directory),
        : "ebx"
    );
}
