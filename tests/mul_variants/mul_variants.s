.section .text
.globl _start
_start:
    lui     x30, 0x10000

    addi    x1, x0, 7
    addi    x2, x0, -3
    mul     x3, x1, x2
    addi    x4, x0, -21
    bne     x3, x4, fail

    addi    x1, x0, -2
    lui     x2, 0x40000
    mulh    x3, x1, x2
    addi    x4, x0, -1
    bne     x3, x4, fail

    lui     x2, 0x80000
    mulhsu  x3, x1, x2
    bne     x3, x4, fail

    addi    x1, x0, -1
    addi    x2, x0, 2
    mulhu   x3, x1, x2
    addi    x4, x0, 1
    bne     x3, x4, fail

pass:
    addi    x1, x0, 1
    sw      x1, 0(x30)
    jal     x0, hang

fail:
    addi    x1, x0, 2
    sw      x1, 0(x30)

hang:
    jal     x0, hang
