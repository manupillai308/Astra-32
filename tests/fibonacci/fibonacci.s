.section .text
.globl _start
_start:
    lui     x29, 0x80000
    lui     x30, 0x10000

    addi    x1,  x0, 0
    addi    x2,  x0, 1
    addi    x3,  x0, 10
    addi    x4,  x29, 0

    sw      x1,  0(x4)
    addi    x4,  x4, 4
    sw      x2,  0(x4)
    addi    x4,  x4, 4
    addi    x3,  x3, -2

loop:
    beq     x3,  x0, check
    add     x5,  x1, x2
    sw      x5,  0(x4)
    addi    x4,  x4, 4
    add     x1,  x0, x2
    add     x2,  x0, x5
    addi    x3,  x3, -1
    jal     x0,  loop

check:
    addi    x4,  x29, 0
    lw      x5,  0(x4)
    bne     x5,  x0, fail
    lw      x5,  4(x4)
    addi    x6,  x0, 1
    bne     x5,  x6, fail
    lw      x5,  8(x4)
    bne     x5,  x6, fail
    lw      x5,  12(x4)
    addi    x6,  x0, 2
    bne     x5,  x6, fail
    lw      x5,  16(x4)
    addi    x6,  x0, 3
    bne     x5,  x6, fail
    lw      x5,  20(x4)
    addi    x6,  x0, 5
    bne     x5,  x6, fail
    lw      x5,  24(x4)
    addi    x6,  x0, 8
    bne     x5,  x6, fail
    lw      x5,  28(x4)
    addi    x6,  x0, 13
    bne     x5,  x6, fail
    lw      x5,  32(x4)
    addi    x6,  x0, 21
    bne     x5,  x6, fail
    lw      x5,  36(x4)
    addi    x6,  x0, 34
    bne     x5,  x6, fail
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
