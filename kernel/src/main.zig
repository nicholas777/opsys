const console = @import("console.zig");
const panic = @import("common.zig").panic;
const gdt = @import("gdt.zig");
const memory = @import("memory.zig");
const heap = @import("heap.zig");
const int = @import("interrupts.zig");
const pic = @import("pic.zig");
const mb = @import("multiboot.zig");

pub fn kmain(magic: u32, multiboot: *const mb.Multiboot) callconv(.C) void {
    asm volatile ("cli");
    console.initialize();

    if (magic != 0x2BADB002) {
        panic("Invalid multiboot magic number");
    }

    console.printf("Entered kmain()\n", .{});

    // Init the GDT
    gdt.initGdt();
    console.printf("GDT initialized\n", .{});

    if (multiboot.flags & mb.FlagMmap == 0) {
        panic("No multiboot memory map");
    }

    // Paging
    memory.initPaging(multiboot.mmap_addr, multiboot.mmap_length);
    while (true) {}
    console.printf("Paging on\n", .{});

    const alloc = heap.KernelAllocator;
    _ = alloc;

    const pic1_mask: u16 = 0b11111011;
    const pic2_mask: u16 = 0b11111111;
    pic.initPic(0x20, pic1_mask | (pic2_mask << 8));

    int.initInterrupts();
    asm volatile ("sti");
    console.putline("Interrupts on");
}
