const std = @import("std");

const console = @import("console.zig");
const panic = @import("common.zig").panic;
const gdt = @import("gdt.zig");
const memory = @import("memory.zig");
const heap = @import("heap.zig");
const int = @import("interrupts.zig");
const pic = @import("pic.zig");
const mb = @import("multiboot.zig");

var mb_copy: mb.Multiboot linksection(".bss") = undefined;

fn getPage(addr: usize) usize {
    return addr - (addr % memory.PAGE_SIZE);
}

pub fn kmain(magic: u32, mb_struct: *mb.Multiboot) callconv(.C) void {
    asm volatile ("cli");
    console.initialize();

    if (magic != 0x2BADB002) {
        panic("Invalid multiboot magic number");
    }

    console.printf("Entered kmain()\n", .{});

    const multiboot = &mb_copy;
    @memcpy(std.mem.asBytes(multiboot), std.mem.asBytes(mb_struct));

    if (multiboot.flags & mb.FlagBootloaderName != 0) {
        var index: usize = 0;
        while (multiboot.bootloader_name[index] != 0) : (index += 1) {}
        console.printf("Kernel loaded by {s}\n", .{
            multiboot.bootloader_name[0..index],
        });
    }

    // Init the GDT
    gdt.initGdt();
    console.printf("GDT initialized\n", .{});

    if (multiboot.flags & mb.FlagMmap == 0) {
        panic("No multiboot memory map");
    }

    // Paging
    memory.initPaging(multiboot.mmap_addr, multiboot.mmap_length);
    console.printf("Paging on\n", .{});

    const mmap_offset: usize = @intFromPtr(multiboot.mmap_addr) % memory.PAGE_SIZE;
    multiboot.mmap_addr = @ptrFromInt(memory.mapPageAt(
        .KernelRO,
        getPage(@intFromPtr(multiboot.mmap_addr)),
    ) + mmap_offset);

    const alloc = heap.KernelAllocator;
    _ = alloc;

    const pic1_mask: u16 = 0b11111011;
    const pic2_mask: u16 = 0b11111111;
    pic.initPic(0x20, pic1_mask | (pic2_mask << 8));

    int.initInterrupts();
    asm volatile ("sti");
    console.putline("Interrupts on");

    // Detecting hardware

    // Figure out the root device
    if (multiboot.flags & mb.FlagBootDevice == 0) {
        panic("Boot device not supplied by multiboot");
    }
}
