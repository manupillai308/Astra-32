.section .text
.globl _start
_start:
    lui     x29, 0x80000
    lui     x30, 0x10000

    addi    x1,  x0, -1

    sb      x1,  0(x29)
    sh      x1,  2(x29)
    sw      x1,  4(x29)

    lb      x2,  0(x29)
    lbu     x3,  0(x29)
    lh      x4,  2(x29)
    lhu     x5,  2(x29)
    lw      x6,  4(x29)

    addi    x7,  x0, 0x12
    sb      x7,  8(x29)
    lb      x8,  8(x29)

    addi    x9,  x0, -1
    bne     x2,  x9, fail
    addi    x9,  x0, 255
    bne     x3,  x9, fail
    addi    x9,  x0, -1
    bne     x4,  x9, fail
    lui     x9,  0x10
    addi    x9,  x9, -1
    bne     x5,  x9, fail
    addi    x9,  x0, -1
    bne     x6,  x9, fail
    addi    x9,  x0, 0x12
    bne     x8,  x9, fail
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
