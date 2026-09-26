/* SPDX-License-Identifier: GPL-2.0-only */
/* Linux arm64 Image envelope; this payload is a standalone hardware probe. */
.section .head, "ax"
.global _start
_start:
    b entry
    .long 0
    .quad 0x80000
    .quad image_end - _start
    .quad 2 /* little endian, 4 KiB pages, physical placement flag clear */
    .quad 0, 0, 0
    .long 0x644d5241
    .long 0
entry:
    msr daifset, #15
    mrs x20, CurrentEL
    cmp x20, #4
    b.eq 1f
    cmp x20, #8
    b.ne probe_reset
    mrs x9, sctlr_el2
    adr x10, vectors
    msr vbar_el2, x10
    b 2f
1:
    mrs x9, sctlr_el1
    adr x10, vectors
    msr vbar_el1, x10
2:
    isb
    /* Require Linux boot protocol: MMU and data cache disabled. */
    tst x9, #1
    b.ne probe_reset
    tst x9, #4
    b.ne probe_reset
    adr x9, stack_top
    mov sp, x9
    mov x1, x20
    bl probe_main /* x0 retains the FDT pointer; x1 is CurrentEL */
.global probe_reset
probe_reset:
    dsb sy
    mov x0, #9
    movk x0, #0x8400, lsl #16 /* PSCI SYSTEM_RESET, DT conduit smc */
    mov x1, #0
    mov x2, #0
    mov x3, #0
    smc #0
3:  wfe
    b 3b

.balign 2048
vectors:
.rept 16
    b exception
    .balign 128
.endr
exception:
    mrs x9, CurrentEL
    cmp x9, #4
    b.eq 4f
    cmp x9, #8
    b.ne probe_reset
    mrs x9, sctlr_el2
    tbnz x9, #0, probe_reset
    tbnz x9, #2, probe_reset
    mrs x0, esr_el2
    mrs x1, elr_el2
    mrs x2, far_el2
    b 5f
4:
    mrs x9, sctlr_el1
    tbnz x9, #0, probe_reset
    tbnz x9, #2, probe_reset
    mrs x0, esr_el1
    mrs x1, elr_el1
    mrs x2, far_el1
5:
    adr x9, stack_top
    mov sp, x9
    b probe_exception
.section .stack, "aw", %progbits
.balign 16
    .space 16384
stack_top:
