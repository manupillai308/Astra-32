.section .text
.globl _start
_start:
    lui     x29, 0x80000
    lui     x30, 0x10000

    addi    x5,  x0, 0x5a5
    addi    x6,  x0, 0x6b6

    sw      x5,  0(x29)
    sw      x6,  8(x29)

    lw      x7,  0(x29)
    lw      x8,  8(x29)

    bne     x7,  x5, fail
    bne     x8,  x6, fail
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
