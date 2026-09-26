/* SPDX-License-Identifier: GPL-2.0-only */
ENTRY(_start)
SECTIONS {
    . = 0;
    .head : { KEEP(*(.head)) }
    .text : { *(.text*) }
    .rodata : { *(.rodata*) }
    .data : { *(.data*) }
    .bss : { *(.bss*) *(COMMON) }
    .stack : { *(.stack) }
    . = ALIGN(4096);
    image_end = .;
    /DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) }
}
