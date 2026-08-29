.section .text
.globl _start
_start:
    lui     x29, 0x80000
    lui     x30, 0x10000

    addi    x1,  x0, -1
    sw      x1,  0(x29)

    addi    x2,  x0, 0x12
    sb      x2,  1(x29)

    addi    x3,  x0, 0x34
    sh      x3,  2(x29)

    lw      x4,  0(x29)

    lui     x5,  0x00341
    addi    x5,  x5, 0x2ff
    bne     x4,  x5, fail
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
