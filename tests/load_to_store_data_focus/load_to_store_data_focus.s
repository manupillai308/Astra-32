.section .text
.globl _start
_start:
    lui     x29, 0x80000
    lui     x30, 0x10000

    addi    x1,  x0, 9
    sw      x1,  0(x29)

    lw      x2,  0(x29)
    sw      x2,  4(x29)
    lw      x3,  4(x29)

    addi    x4,  x0, 9
    bne     x2,  x4, fail
    bne     x3,  x4, fail
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
