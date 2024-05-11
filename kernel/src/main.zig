const console = @import("console.zig");
const gdt = @import("gdt.zig");
const memory = @import("memory.zig");
const heap = @import("heap.zig");

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
    var mem = alloc.alloc(u8, 5) catch unreachable;
    mem[0] = 'A';
    mem[1] = 'B';
    mem[2] = 'C';
    mem[3] = 'D';
    mem[4] = 'E';
    console.printf("{s}\n", .{mem});
}
