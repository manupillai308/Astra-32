.section .text
.globl _start
_start:
    lui     x30, 0x10000

    addi    x1,  x0, 0
    addi    x2,  x0, 0x55
    csrrw   x3,  mscratch, x2
    bne     x3,  x1, fail

    csrrs   x4,  mscratch, x0
    bne     x4,  x2, fail

    addi    x5,  x0, 0x22
    csrrw   x6,  mscratch, x5
    bne     x6,  x2, fail

    csrrs   x7,  mscratch, x0
    bne     x7,  x5, fail

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
