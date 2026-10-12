.section .text
.globl _start
_start:
    lui     x29, 0x80000
    lui     x30, 0x10000

    addi    x1, x0, 10
    sw      x1, 0(x29)

    addi    x2, x0, 5
    amoadd.w x3, x2, (x29)
    addi    x4, x0, 10
    bne     x3, x4, fail
    lw      x5, 0(x29)
    addi    x4, x0, 15
    bne     x5, x4, fail

    addi    x2, x0, 7
    amoswap.w x3, x2, (x29)
    addi    x4, x0, 15
    bne     x3, x4, fail
    lw      x5, 0(x29)
    bne     x5, x2, fail

    addi    x2, x0, 3
    amoxor.w x3, x2, (x29)
    addi    x4, x0, 7
    bne     x3, x4, fail
    lw      x5, 0(x29)
    addi    x4, x0, 4
    bne     x5, x4, fail

    addi    x2, x0, 6
    amoand.w x3, x2, (x29)
    addi    x4, x0, 4
    bne     x3, x4, fail
    lw      x5, 0(x29)
    bne     x5, x4, fail

    addi    x2, x0, 2
    amoor.w x3, x2, (x29)
    addi    x4, x0, 4
    bne     x3, x4, fail
    lw      x5, 0(x29)
    addi    x4, x0, 6
    bne     x5, x4, fail

    addi    x1, x0, 5
    sw      x1, 0(x29)
    addi    x2, x0, -2
    amomin.w x3, x2, (x29)
    bne     x3, x1, fail
    lw      x5, 0(x29)
    bne     x5, x2, fail

    addi    x2, x0, 3
    amomax.w x3, x2, (x29)
    addi    x4, x0, -2
    bne     x3, x4, fail
    lw      x5, 0(x29)
    bne     x5, x2, fail

    addi    x1, x0, -1
    sw      x1, 0(x29)
    addi    x2, x0, 4
    amominu.w x3, x2, (x29)
    bne     x3, x1, fail
    lw      x5, 0(x29)
    bne     x5, x2, fail

    addi    x1, x0, 4
    sw      x1, 0(x29)
    addi    x2, x0, -1
    amomaxu.w x3, x2, (x29)
    bne     x3, x1, fail
    lw      x5, 0(x29)
    bne     x5, x2, fail

pass:
    addi    x1, x0, 1
    sw      x1, 0(x30)
    jal     x0, hang

fail:
    addi    x1, x0, 2
    sw      x1, 0(x30)

hang:
    jal     x0, hang
