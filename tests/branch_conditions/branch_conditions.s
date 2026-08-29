.section .text
.globl _start
_start:
    lui     x30, 0x10000

    addi    x1,  x0, 5
    addi    x2,  x0, 5
    addi    x3,  x0, 7
    addi    x4,  x0, -1
    addi    x5,  x0, 1
    addi    x10, x0, 0
    addi    x11, x0, 0

    beq     x1,  x2, beq_ok
    addi    x10, x0, 1
beq_ok:
    addi    x11, x11, 1

    bne     x1,  x3, bne_ok
    addi    x10, x0, 2
bne_ok:
    addi    x11, x11, 1

    blt     x4,  x5, blt_ok
    addi    x10, x0, 3
blt_ok:
    addi    x11, x11, 1

    bge     x5,  x4, bge_ok
    addi    x10, x0, 4
bge_ok:
    addi    x11, x11, 1

    bltu    x5,  x4, bltu_ok
    addi    x10, x0, 5
bltu_ok:
    addi    x11, x11, 1

    bgeu    x4,  x5, bgeu_ok
    addi    x10, x0, 6
bgeu_ok:
    addi    x11, x11, 1

    bne     x10, x0, fail
    addi    x12, x0, 6
    bne     x11, x12, fail
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
