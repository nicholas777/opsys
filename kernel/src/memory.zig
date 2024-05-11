const std = @import("std");

var physical_mmap: [1024 * 1024 / 8]u8 = undefined;

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
    const index = addr / PAGE_SIZE;
    const bit = index & 8;

    return (physical_mmap[index] >> bit) & 0x1 == PAGE_USED;
}

pub fn freePhysicalPage(addr: usize) void {
    const index = addr / PAGE_SIZE;
    const bit = index & 8;

    physical_mmap[index] &= -bit;
}

fn markPagesUsed(start: usize, end: usize) void {
    const start_page = start / PAGE_SIZE;
    const end_page = end / PAGE_SIZE + 1;

    var i = start_page / 8;
    while (i <= end_page / 8) : (i += 1) {
        physical_mmap[i] = 0xFF;
    }
}

fn markPageUsed(addr: usize) void {
    const index = addr / PAGE_SIZE;
    const bit = index % 8;

    physical_mmap[index] |= PAGE_USED << @intCast(bit);
}

extern const kernel_start: usize;
extern const kernel_end: usize;

var page_directory: [1024]u32 align(4096) linksection(".bss") = undefined;

fn present(entry: u32) bool {
    return entry & 0x1 == 1;
}

pub const PageTableType = enum(u8) {
    KernelRO = 0b00100001,
    KernelRW = 0b00000011,
    UserRO = 0b00100101,
    UserRW = 0b00100111,
};

const PAGE_FLAG: u32 = 0x3FF;

const panic = @import("common.zig").panic;

fn registerPT(i: usize, pt_type: PageTableType) usize {
    const addr = allocPhysicalPage();

    page_directory[i] = addr | @intFromEnum(pt_type);
    @as([*]u32, @ptrFromInt(page_directory[1023] & (~PAGE_FLAG)))[i] = addr | @intFromEnum(pt_type);

    return addr;
}

pub fn mapPage(pt_type: PageTableType) usize {
    return mapPageAt(pt_type, allocPhysicalPage());
}

fn mapPageAt(pt_type: PageTableType, addr: usize) usize {
    var i: usize = 0;
    var j: usize = 0;

    while (i <= 1023) : (i += 1) {
        if (i == 1023) break;
        if (!present(page_directory[i])) break;

        const pt = @as([*]u32, @ptrFromInt(page_directory[i] & (~PAGE_FLAG)));
        while (j <= 1024) : (j += 1) {
            if (j == 1024) break;
            if (!present(pt[j])) break;
        }

        if (j != 1024) break;
        j = 0;
    }

    if (i == 1023) panic("Out of memory in page directory");

    var pt: [*]u32 = undefined;
    if (!present(page_directory[i])) {
        pt = @as([*]u32, @ptrFromInt(registerPT(i, pt_type)));
    } else {
        pt = @as([*]u32, @ptrFromInt(page_directory[i]));
    }

    pt[i] = addr | @intFromEnum(pt_type);
    return addr;
}

fn mapPageAtTo(pt_type: PageTableType, addr: usize, virtual: usize) usize {
    const pde = virtual >> 22;
    const pte = (virtual >> 12) & 0x3FF;

    var pt: [*]u32 = undefined;
    if (!present(page_directory[pde])) {
        pt = @as([*]u32, @ptrFromInt(registerPT(pde, pt_type)));
    } else {
        pt = @as([*]u32, @ptrFromInt(page_directory[pde] & (~PAGE_FLAG)));
    }

    pt[pte] = addr | @intFromEnum(pt_type);

    return addr;
}

const console = @import("console.zig");
const heap = @import("heap.zig");

pub fn initPaging() void {
    markPagesUsed(0, 8 * PAGE_SIZE);
    markPagesUsed(@intFromPtr(&kernel_start), @intFromPtr(&kernel_end));

    // The last page table is used to map the other page tables
    const pt_addr = allocPhysicalPage();
    const page_ptr = @as([*]u32, @ptrFromInt(pt_addr));

    page_directory[1023] = pt_addr | @intFromEnum(PageTableType.KernelRW);
    page_ptr[1023] = pt_addr | @intFromEnum(PageTableType.KernelRW);

    // Now we just need to map the kernel itself
    const kstart_page = @intFromPtr(&kernel_start) / PAGE_SIZE;
    const kend_page = @intFromPtr(&kernel_end) / PAGE_SIZE + 1;
    const kpages = kend_page - kstart_page;

    console.printf("Kernel start: {x}\nKernel end: {x}\nKernel size: {} pages\n", .{
        @intFromPtr(&kernel_start),
        @intFromPtr(&kernel_end),
        kpages,
    });

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
        \\ cli
        \\ movl %[pd], %cr3
        \\ movl %cr0, %ebx
        \\ orl $0x80000001, %ebx
        \\ movl %ebx, %cr0
        :
        : [pd] "{eax}" (&page_directory),
        : "ebx"
    );
}