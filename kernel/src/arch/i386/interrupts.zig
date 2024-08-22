const gdt = @import("gdt.zig");
const console = @import("../../console.zig");

pub const Context = extern struct {
    edi: u32,
    esi: u32,
    ebp: u32,
    esp: u32,
    ebx: u32,
    edx: u32,
    ecx: u32,
    eax: u32,
    int: u32, // Interrupt number
    error_code: u32,
    eip: u32,
    cs: u32,
    eflags: u32,
};

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
pub const InterruptHandler = fn (?*anyopaque) void;

var idt: [256]Gate = undefined;
var handlers: [256]?*const InterruptHandler = undefined;
var contexts: [256]?*anyopaque = undefined;

fn createGate(addr: usize, present: bool, gate_type: GateType) Gate {
    const p_flag: u8 = if (present) 0b10000000 else 0b0;

    return Gate{
        .offset1 = @intCast(addr >> 16),
        .ss = gdt.CodeSS,
        .access = 0b00001000 | p_flag | @intFromEnum(gate_type),
        .offset2 = @intCast(addr & 0xFFFF),
    };
}

export fn c_installInterruptHandler(h: ?*anyopaque, n: usize, c: ?*anyopaque) void {
    installInterruptHandler(@ptrCast(h.?), n, c);
}

pub fn installInterruptHandler(
    h: *const InterruptHandler,
    n: usize,
    context: ?*anyopaque,
) void {
    handlers[n] = h;
    contexts[n] = context;
}

pub export fn uninstallInterruptHandler(n: usize) void {
    handlers[n] = null;
    contexts[n] = null;
}

extern fn interruptHandler() void;

const interruptSize = 0xb;

pub fn initInterrupts() void {
    var i: usize = 0;
    while (i < idt.len) : (i += 1) {
        idt[i] = createGate(
            @intFromPtr(&interruptHandler) + i * interruptSize,
            true,
            .InterruptGate,
        );
        handlers[i] = null;
    }

    idtr.offset = @intFromPtr(&idt);
    idtr.size = @sizeOf(@TypeOf(idt));

    asm volatile (
        \\ cli
        \\ lidtl (%[idtr])
        :
        : [idtr] "{eax}" (&idtr),
    );
}

export fn dispatchInterrupt(ctx: *Context) callconv(.C) void {
    if (handlers[ctx.int]) |handler| {
        handler(contexts[ctx.int]);
    }
}
