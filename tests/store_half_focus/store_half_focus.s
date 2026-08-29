.section .text
.globl _start
_start:
    lui     x29, 0x80000
    lui     x30, 0x10000

    addi    x1,  x0, -1

    sb      x1,  0(x29)
    sh      x1,  2(x29)

    lb      x2,  0(x29)
    lh      x3,  2(x29)
    lhu     x4,  2(x29)

    addi    x5,  x0, -1
    bne     x2,  x5, fail
    bne     x3,  x5, fail
    lui     x5,  0x10
    addi    x5,  x5, -1
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
    jal     x0,  hang
