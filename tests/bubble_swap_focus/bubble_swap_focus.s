.section .text
.globl _start
_start:
    lui     x29, 0x80000
    lui     x30, 0x10000

    addi    x1,  x0, 5
    sw      x1,  0(x29)
    addi    x1,  x0, 2
    sw      x1,  4(x29)

    addi    x15, x29, 0
    lw      x17, 0(x15)
    lw      x18, 4(x15)
    bge     x18, x17, no_swap
    sw      x18, 0(x15)
    sw      x17, 4(x15)

no_swap:
    lw      x2,  0(x29)
    lw      x3,  4(x29)
    addi    x4,  x0, 2
    bne     x2,  x4, fail
    addi    x4,  x0, 5
    bne     x3,  x4, fail
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
