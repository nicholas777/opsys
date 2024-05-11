const console = @import("console.zig");

pub fn panic(msg: []const u8) noreturn {
    console.setColor(console.vgaColor(.White, .Red));
    console.puts(msg);
    while (true) {}
}
