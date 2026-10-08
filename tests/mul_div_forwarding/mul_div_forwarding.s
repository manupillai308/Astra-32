.section .text
.globl _start
_start:
    lui     x30, 0x10000

    addi    x1, x0, 6
    addi    x2, x0, 7
    mul     x3, x1, x2
    addi    x4, x3, 1
    addi    x5, x0, 43
    bne     x4, x5, fail

    mul     x6, x3, x2
    addi    x7, x0, 294
    bne     x6, x7, fail

    div     x8, x6, x2
    bne     x8, x3, fail

pass:
    addi    x1, x0, 1
    sw      x1, 0(x30)
    jal     x0, hang

fail:
    addi    x1, x0, 2
    sw      x1, 0(x30)

hang:
    jal     x0, hang
