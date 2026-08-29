.section .text
.globl _start
_start:
    lui     x29, 0x80000
    lui     x30, 0x10000

    addi    x1,  x0, 7
    sw      x1,  0(x29)

    lw      x2,  0(x29)
    addi    x3,  x2, 3
    add     x4,  x2, x2
    sw      x3,  4(x29)

    addi    x5,  x0, 7
    bne     x2,  x5, fail
    addi    x5,  x0, 10
    bne     x3,  x5, fail
    lw      x6,  4(x29)
    bne     x6,  x5, fail
    addi    x5,  x0, 14
    bne     x4,  x5, fail
    jal     x0,  pass

pass:
    addi    x1,  x0, 1
    sw      x1,  0(x30)
    jal     x0,  hang

fail:
    addi    x1,  x0, 2
    sw      x1,  0(x30)

hang:
    jal     x0, hang
