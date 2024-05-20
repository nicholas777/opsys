const console = @import("console.zig");

pub fn panic(msg: []const u8) noreturn {
    console.setColor(console.vgaColor(.White, .Red));
    console.puts(msg);
    while (true) {}
}

pub fn outb(port: u16, value: u32) void {
    asm volatile ("outb %[port]"
        :
        : [port] "{edx}" (port),
          [eax] "{eax}" (value),
    );
}

pub fn inb(port: u16) u32 {
    return asm volatile ("inb %[port]"
        : [out] "={eax]" (-> u32),
        : [port] "{edx}" (port),
    );
}
