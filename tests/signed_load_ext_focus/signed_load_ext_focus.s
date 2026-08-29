.section .text
.globl _start
_start:
    lui     x29, 0x80000
    lui     x30, 0x10000

    addi    x1,  x0, 0x80
    sb      x1,  0(x29)
    addi    x1,  x0, -1
    sb      x1,  1(x29)
    sb      x0,  2(x29)
    addi    x1,  x0, 0x80
    sb      x1,  3(x29)

    lb      x2,  0(x29)
    lbu     x3,  0(x29)
    lb      x4,  1(x29)
    lbu     x5,  1(x29)
    lh      x6,  2(x29)
    lhu     x7,  2(x29)

    addi    x8,  x0, -128
    bne     x2,  x8, fail
    addi    x8,  x0, 128
    bne     x3,  x8, fail
    addi    x8,  x0, -1
    bne     x4,  x8, fail
    addi    x8,  x0, 255
    bne     x5,  x8, fail
    lui     x8,  0xffff8
    bne     x6,  x8, fail
    lui     x8,  0x8
    bne     x7,  x8, fail
    jal     x0,  pass

pass:
    addi    x1,  x0, 1
    sw      x1,  0(x30)
    jal     x0, hang

fail:
    addi    x1,  x0, 2
    sw      x1,  0(x30)

hang:
    jal     x0, hang
