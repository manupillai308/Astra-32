.section .text
.globl _start
_start:
    lui     x29, 0x80000
    lui     x30, 0x10000

    addi    x1,  x29, 16
    sw      x1,  0(x29)

    addi    x2,  x0, 11
    lw      x3,  0(x29)
    sw      x2,  0(x3)
    lw      x4,  16(x29)

    addi    x5,  x0, 11
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
