const GDTR = packed struct {
    size: u16,
    offset: u32,
};

var gdtr align(4) = GDTR{
    .offset = 0,
    .size = 0,
};

pub const SegmentDescriptor = packed struct {
    limit0: u16,
    base0: u16,
    base1: u8,
    access: u8,
    limit1: u4,
    flags: u4,
    base2: u8,
};

// Intel manual 3A - 3.4.5.1
pub const SegmentType = enum(u8) {
    ro_data = 0b0001,
    rw_data = 0b0011,
    ro_ed_data = 0b0101,
    rw_ed_data = 0b0111,
    exec_code = 0b1001,
    read_exec_code = 0b1011,
    conf_exec_code = 0b1101,
    read_conf_code = 0b1111,
};

pub const RingLevel = enum(u8) {
    ring0 = 0 << 5,
    ring1 = 1 << 5,
    ring2 = 2 << 5,
    ring3 = 3 << 5,
};

const std = @import("std");

var gdt align(4) = [1]SegmentDescriptor{std.mem.zeroes(SegmentDescriptor)} ** 5;

fn create_sd(base: u32, limit: u20, privilege: RingLevel, segtype: SegmentType) SegmentDescriptor {
    return SegmentDescriptor{
        .limit0 = @intCast(limit & 0xFFFF),
        .base0 = @intCast(base & 0xFF),
        .base1 = @intCast((base >> 16) & 0xFF),
        .access = @intFromEnum(segtype) | 0b10010000 | @intFromEnum(privilege),
        .limit1 = @intCast(limit >> 16),
        .flags = 0b1101,
        .base2 = @intCast(base >> 24),
    };
}

comptime {
    asm (
        \\ .globl reload_gdt
        \\ .type reload_gdt, @function
        \\ reload_gdt:
        \\     movl 4(%esp), %ecx
        \\     lgdtl (%ecx)
        \\
        \\     movw $0x8, %ax
        \\     movw %ax, %ds
        \\     movw %ax, %es
        \\     movw %ax, %fs
        \\     movw %ax, %gs
        \\     movw %ax, %ss
        \\
        \\     jmpl $0x10, $flush_cs
        \\ flush_cs:
        \\     ret
    );
}

pub const CodeSS = 0x10;
pub const DataSS = 0x8;

const console = @import("console.zig");

pub fn initGdt() void {
    gdt[1] = create_sd(0, 0xFFFFF, .ring0, .rw_data);
    gdt[2] = create_sd(0, 0xFFFFF, .ring0, .read_exec_code);
    gdt[3] = create_sd(0, 0xFFFFF, .ring3, .rw_data);
    gdt[4] = create_sd(0, 0xFFFFF, .ring3, .read_exec_code);

    gdtr.size = @sizeOf(@TypeOf(gdt)) - 1;
    gdtr.offset = @intFromPtr(&gdt);

    asm volatile (
        \\ pushl %[gdtr]
        \\ call reload_gdt
        \\ addl $4, %esp
        :
        : [gdtr] "{ebx}" (&gdtr),
    );
}
