.section .data

# Lookup table for whether there is an error code
lookup_table:
.byte 0, 0, 0, 0, 0, 0, 0, 0
.byte 1, 0, 1, 1, 1, 1, 1, 0
.byte 0, 1, 0, 0, 0, 1, 0, 0
.byte 0, 0, 0, 0, 0, 0, 0, 0

.zero 256 - 32 # The other interrupts are user defined

tmp:
.long 0, 0

.section .text

.extern dispatchInterrupt

.macro isr n, end
    pushl \n
    jmp interrupt
.if \end - \n
    isr "(\n+1)", \end
.endif
.endm

.type interruptHandler, @function
.globl interruptHandler
interruptHandler:
    # This is needed because we can only nest 20 times
    isr 0,   16 - 1
    isr 16,  32 - 1
    isr 32,  48 - 1
    isr 48,  64 - 1
    isr 64,  80 - 1
    isr 80,  96 - 1
    isr 96,  112 - 1
    isr 112, 128 - 1
    isr 128, 144 - 1
    isr 144, 160 - 1
    isr 160, 176 - 1
    isr 176, 192 - 1
    isr 192, 208 - 1
    isr 208, 224 - 1
    isr 224, 240 - 1
    isr 240, 256 - 1
interrupt:
    movl $0, %ebx
    xorl %eax, %eax
    xorl %edx, %edx
    divl %ebx

    movl %eax, (tmp)
    movl %ebx, tmp + 4

    movl 4(%esp), %eax # Int number
    leal lookup_table, %ebx
    movb (%ebx, %eax), %al

    jnz call_dispatch
    popl %eax
    pushl $0
    pushl %eax

call_dispatch:
    movl (tmp), %eax
    movl tmp + 4, %ebx

    pushal

    movl %esp, %eax
    addl $52, %eax
    pushl %eax
    call dispatchInterrupt
    addl $4, %esp

    popal
    addl $8, %esp # Error code and interrupt number

    iret
