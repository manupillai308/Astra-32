.section .text
.globl _start
_start:
    lui     x30, 0x10000

    csrrwi  x0,  mscratch, 3
    csrrsi  x1,  mscratch, 4
    addi    x2,  x0, 3
    bne     x1,  x2, fail

    csrrci  x3,  mscratch, 1
    addi    x4,  x0, 7
    bne     x3,  x4, fail

    csrrsi  x5,  mscratch, 0
    addi    x6,  x0, 6
    bne     x5,  x6, fail

    csrrci  x7,  mscratch, 0
    bne     x7,  x6, fail

    addi    x8,  x0, 0x12
    csrrw   x0,  mscratch, x8
    csrrw   x9,  mscratch, x6
    bne     x9,  x8, fail

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
