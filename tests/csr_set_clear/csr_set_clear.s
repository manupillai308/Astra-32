.section .text
.globl _start
_start:
    lui     x30, 0x10000

    addi    x1,  x0, 0x0f
    csrrw   x0,  mscratch, x1

    addi    x2,  x0, 0x30
    csrrs   x3,  mscratch, x2
    bne     x3,  x1, fail

    addi    x4,  x0, 0x3f
    csrrs   x5,  mscratch, x0
    bne     x5,  x4, fail

    addi    x6,  x0, 0x0c
    csrrc   x7,  mscratch, x6
    bne     x7,  x4, fail

    addi    x8,  x0, 0x33
    csrrs   x9,  mscratch, x0
    bne     x9,  x8, fail

    csrrc   x10, mscratch, x0
    bne     x10, x8, fail

    csrrs   x11, mscratch, x0
    bne     x11, x8, fail

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
