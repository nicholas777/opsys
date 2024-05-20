const console = @import("console.zig");
const gdt = @import("gdt.zig");
const memory = @import("memory.zig");
const heap = @import("heap.zig");
const int = @import("interrupts.zig");
const pic = @import("pic.zig");

pub fn kmain() void {
    console.initialize();
    console.printf("Entered kmain()\n", .{});

    // Init the GDT
    gdt.initGdt();
    console.printf("GDT initialized\n", .{});

    // Paging
    memory.initPaging();
    console.printf("Paging on\n", .{});

    const alloc = heap.KernelAllocator;
    _ = alloc;

    // Disable everything but keyboard
    const pic1_mask: u16 = 0b11111001;
    const pic2_mask: u16 = 0b11111111;
    pic.initPic(0x20, pic1_mask | (pic2_mask << 8));

    int.initInterrupts();
    asm volatile ("sti");
    console.putline("Interrupts on");
}
