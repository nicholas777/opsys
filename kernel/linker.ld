ENTRY(_start)
 
SECTIONS {
    . = 1M;
 
    kernel_start = .;
    .multiboot : ALIGN(4K) {
        KEEP(*(.multiboot))
    }

    /* . += 12; */
 
    .text . : ALIGN(4K) {
        *(.text*)
    }
 
    .rodata  .: ALIGN(4K) {
        *(.rodata*)
    }
 
    .data : ALIGN(4K) {
        *(.data*)
    }
 
    .bss : ALIGN(4K) {
        *(COMMON)
        *(.bss*)
    }

    .debug : ALIGN(4K) {
        *(.debug*)
        *(.comment)
    }

    kernel_end = .;
}
