.section .text
.globl _start
_start:
    lui     x29, 0x80000
    lui     x30, 0x10000

    addi    x1,  x0, 5
    sw      x1,  0(x29)

    addi    x1,  x0, 2
    sw      x1,  4(x29)

    addi    x1,  x0, 8
    sw      x1,  8(x29)

    addi    x1,  x0, 1
    sw      x1,  12(x29)

    addi    x1,  x0, 4
    sw      x1,  16(x29)

    lw      x2,  0(x29)
    lw      x3,  4(x29)
    lw      x4,  8(x29)
    lw      x5,  12(x29)
    lw      x6,  16(x29)

    addi    x7,  x0, 5
    bne     x2,  x7, fail
    addi    x7,  x0, 2
    bne     x3,  x7, fail
    addi    x7,  x0, 8
    bne     x4,  x7, fail
    addi    x7,  x0, 1
    bne     x5,  x7, fail
    addi    x7,  x0, 4
    bne     x6,  x7, fail
    jal     x0,  pass

pass:
    addi    x1,  x0, 1
    sw      x1,  0(x30)
    jal     x0,  hang

fail:
    addi    x1,  x0, 2
    sw      x1,  0(x30)

hang:
    jal     x0,  hang
