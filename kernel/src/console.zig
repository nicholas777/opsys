const fmt = @import("std").fmt;
const Writer = @import("std").io.Writer;

const VGA_WIDTH = 80;
const VGA_HEIGHT = 25;
const VGA_SIZE = VGA_WIDTH * VGA_HEIGHT;

pub const ConsoleColor = enum(u8) {
    Black = 0,
    Blue = 1,
    Green = 2,
    Cyan = 3,
    Red = 4,
    Magenta = 5,
    Brown = 6,
    LightGray = 7,
    DarkGray = 8,
    LightBlue = 9,
    LightGreen = 10,
    LightCyan = 11,
    LightRed = 12,
    LightMagenta = 13,
    LightBrown = 14,
    White = 15,
};

var row: usize = 0;
var column: usize = 0;
var color = vgaColor(ConsoleColor.LightGray, ConsoleColor.Black);
var buffer = @as([*]volatile u16, @ptrFromInt(0xB8000));

pub fn vgaColor(fg: ConsoleColor, bg: ConsoleColor) u8 {
    return @intFromEnum(fg) | (@intFromEnum(bg) << 4);
}

fn vgaEntry(uc: u8, new_color: u8) u16 {
    const c: u16 = new_color;

    return uc | (c << 8);
}

pub fn initialize() void {
    clear();
}

pub fn setColor(new_color: u8) void {
    color = new_color;
}

pub fn clear() void {
    @memset(buffer[0..VGA_SIZE], vgaEntry(' ', color));
}

pub fn putCharAt(c: u8, new_color: u8, x: usize, y: usize) void {
    const index = y * VGA_WIDTH + x;
    buffer[index] = vgaEntry(c, new_color);
}

pub export fn putChar(c: u8) void {
    if (c == '\n') {
        column = 0;
        row += 1;
        if (row == VGA_HEIGHT)
            scroll();
    } else {
        putCharAt(c, color, column, row);
        column += 1;
        if (column == VGA_WIDTH) {
            column = 0;
            row += 1;
            if (row == VGA_HEIGHT)
                scroll();
        }
    }
}

pub fn puts(data: []const u8) void {
    for (data) |c|
        putChar(c);
}

pub fn putline(data: []const u8) void {
    puts(data);
    putChar('\n');
}

export fn c_putline(data: [*]u8) void {
    var len: usize = 0;
    while (data[len] != 0) : (len += 1) {}

    putline(data[0..len]);
}

pub const writer = Writer(void, error{}, callback){ .context = {} };

fn callback(_: void, string: []const u8) error{}!usize {
    puts(string);
    return string.len;
}

pub fn printf(comptime format: []const u8, args: anytype) void {
    fmt.format(writer, format, args) catch unreachable;
}

pub fn scroll() void {
    row = 0;
    while (row != VGA_HEIGHT - 1) : (row += 1) {
        const start = row * VGA_WIDTH;
        const line1 = buffer[start .. start + VGA_WIDTH];
        const line2 = buffer[start + VGA_WIDTH .. start + VGA_WIDTH * 2];
        @memcpy(line1, line2);
    }

    const start = row * VGA_WIDTH;
    const line = buffer[start .. start + VGA_WIDTH];
    @memset(line, 0);

    row = VGA_HEIGHT - 1;
    column = 0;
}
