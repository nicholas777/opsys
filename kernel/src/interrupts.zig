const IDTR = packed struct {
    size: u16,
    offset: u32,
};

var idtr: IDTR = .{ .size = 0, .offset = 0 };

const Gate = packed struct {
    offset1: u16,
    ss: u16,
    filler: u8 = 0,
    access: u8,
    offset2: u16,
};

const GateType = enum(u8) {
    InterruptGate = 0b110,
    TrapGate = 0b111,
};

pub const ISR = fn () callconv(.Naked) void;
pub const InterruptHandler = fn () void;

var idt: [256]Gate = undefined;
var handlers: [256]?*const InterruptHandler = undefined;

const gdt = @import("gdt.zig");

fn createGate(addr: usize, present: bool, gate_type: GateType) Gate {
    const p_flag: u8 = if (present) 0b10000000 else 0b0;

    return Gate{
        .offset1 = @intCast(addr >> 16),
        .ss = gdt.CodeSS,
        .access = 0b00001000 | p_flag | @intFromEnum(gate_type),
        .offset2 = @intCast(addr & 0xFFFF),
    };
}

extern fn isr_8() void;
extern fn isr_11() void;
extern fn isr_13() void;
extern fn isr_14() void;

pub fn initInterrupts() void {
    var i: usize = 0;
    while (i < idt.len) : (i += 1) {
        idt[i] = createGate(0x0, false, .InterruptGate);
        handlers[i] = null;
    }

    handlers[13] = &int13Handler;
    idt[13] = createGate(@intFromPtr(&isr_13), true, .InterruptGate);

    handlers[14] = &int14Handler;
    idt[14] = createGate(@intFromPtr(&isr_14), true, .InterruptGate);

    handlers[8] = &int14Handler;
    idt[8] = createGate(@intFromPtr(&isr_8), true, .InterruptGate);

    handlers[11] = &int14Handler;
    idt[11] = createGate(@intFromPtr(&isr_11), true, .InterruptGate);

    idtr.offset = @intFromPtr(&idt);
    idtr.size = @sizeOf(@TypeOf(idt));

    asm volatile (
        \\ cli
        :
        : [idtr] "{eax}" (&idtr),
        : "eax"
    );
}

export fn intHandler(num: usize) void {
    if (handlers[num] == null) return;
    handlers[num].?();
}

comptime {
    asm (
        \\ .macro reg_isr n
        \\ .globl isr_\n
        \\ .type isr_\n, @function
        \\ isr_\n:
        \\     cli
        \\     pusha
        \\     pushl $\n
        \\     call intHandler
        \\     addl $4, %esp
        \\     popa
        \\     sti
        \\     iret
        \\ .endm
        \\
        \\ reg_isr 8
        \\ reg_isr 11
        \\ reg_isr 13
        \\ reg_isr 14
    );
}

const console = @import("console.zig");

fn int13Handler() void {
    console.printf("int 13\n", .{});
}

fn int14Handler() void {
    //console.printf("int 14\n", .{});
}
