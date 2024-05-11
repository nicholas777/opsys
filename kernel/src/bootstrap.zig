const std = @import("std");

const ALIGN = 1 << 0;
const MEMINFO = 1 << 1;
const MAGIC = 0x1BADB002;
const FLAGS = ALIGN | MEMINFO;

const MultibootHeader = extern struct {
    magic: i32 align(1) = MAGIC,
    flags: i32 align(1),
    checksum: i32 align(1),
};

export const multiboot align(4) linksection(".multiboot") = MultibootHeader{
    .flags = FLAGS,
    .checksum = -(MAGIC + FLAGS),
};

export var stack_bytes: [16 * 1024]u8 align(16) linksection(".bss") = undefined;

const builtin = @import("std").builtin;

const kmain = @import("main.zig").kmain;

export fn _start() callconv(.Naked) noreturn {
    _ = asm volatile (
        \\ mov %[stack], %esp
        \\ mov %esp, %ebp
        \\ calll *%[kmain]
        :
        : [stack] "{ecx}" (@intFromPtr(&stack_bytes) + @sizeOf(@TypeOf(stack_bytes))),
          [kmain] "{ebx}" (@intFromPtr(&kmain)),
    );

    while (true) {}
}
