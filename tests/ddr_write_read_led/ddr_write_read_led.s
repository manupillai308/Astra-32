.section .text
.globl _start
_start:
    lui  x10, 0x80000       # DDR base: 0x80000000
    lui  x11, 0x10000       # LED MMIO: 0x10000000

    addi x5, x0, 0x5a5
    addi x6, x0, 0x6b6

    sw   x5, 0(x10)
    sw   x6, 8(x10)

    lw   x7, 0(x10)
    lw   x8, 8(x10)

    bne  x7, x5, fail
    bne  x8, x6, fail

pass:
    addi x1, x0, 1
    sw   x1, 0(x11)
    jal  x0, hang

fail:
    addi x1, x0, 2
    sw   x1, 0(x11)

hang:
    jal  x0, hang
