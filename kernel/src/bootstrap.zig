const ALIGN = 1 << 0;
const MEMINFO = 1 << 1;
const MAGIC = 0x1BADB002;
const FLAGS = ALIGN | MEMINFO;

const MultibootHeader = extern struct {
    magic: i32 = MAGIC,
    flags: i32,
    checksum: i32,
};

export const multiboot align(4) linksection(".multiboot") = MultibootHeader{
    .flags = FLAGS,
    .checksum = -(MAGIC + FLAGS),
};

export var stack_bytes: [16 * 1024]u8 align(16) linksection(".bss") = undefined;

const kmain = @import("main.zig").kmain;

export fn _start() callconv(.Naked) noreturn {
    _ = asm volatile (
        \\ mov %[stack], %esp
        \\ mov %esp, %ebp
        \\ pushl %ebx
        \\ pushl %eax
        \\ calll *%[kmain]
        \\ addl $8, %esp
        :
        : [stack] "{ecx}" (@intFromPtr(&stack_bytes) + @sizeOf(@TypeOf(stack_bytes))),
          [kmain] "{edx}" (@intFromPtr(&kmain)),
          // This is a hack, multiboot is optimized away
          // unless we use it somehow
          [ebp] "{ebp}" (@intFromPtr(&multiboot)),
    );

    while (true) {}
}
