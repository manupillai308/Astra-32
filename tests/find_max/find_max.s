.section .text
.globl _start
_start:
    lui     x29, 0x80000
    lui     x30, 0x10000

    addi    x1,  x0, 17
    sw      x1,  0(x29)
    addi    x1,  x0, 42
    sw      x1,  4(x29)
    addi    x1,  x0, 8
    sw      x1,  8(x29)
    addi    x1,  x0, 23
    sw      x1,  12(x29)
    addi    x1,  x0, 35
    sw      x1,  16(x29)

    addi    x2,  x29, 0
    addi    x3,  x29, 20
    lw      x4,  0(x2)
    addi    x2,  x2, 4

loop:
    bge     x2,  x3, done
    lw      x5,  0(x2)
    bge     x4,  x5, skip
    add     x4,  x0, x5
skip:
    addi    x2,  x2, 4
    jal     x0,  loop

done:
    sw      x4,  32(x29)
    addi    x6,  x0, 42
    bne     x4,  x6, fail
    lw      x7,  32(x29)
    bne     x7,  x6, fail
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
