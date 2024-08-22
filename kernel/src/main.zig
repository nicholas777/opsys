const std = @import("std");

const console = @import("console.zig");
const panic = @import("common.zig").panic;
const gdt = @import("arch/i386/gdt.zig");
const memory = @import("arch/i386/memory.zig");
const heap = @import("heap.zig");
const int = @import("arch/i386/interrupts.zig");
const pic = @import("pic.zig");
const mb = @import("multiboot.zig");
const acpica = @import("acpica/acpica.zig");

var mb_copy: mb.Multiboot linksection(".bss") = undefined;

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

    // Needs to be done before paging is enabled
    acpica.findRsdp();

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
        @intFromPtr(multiboot.mmap_addr) - mmap_offset,
    ) + mmap_offset);

    const alloc = heap.KernelAllocator;
    _ = alloc;

    acpica.initializeAcpica();
    console.putline("Initialized acpica");

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
