.section .text
.globl _start
_start:
    lui     x29, 0x80000
    lui     x30, 0x10000

    addi    x1,  x0, 5
    sw      x1,  0(x29)
    addi    x1,  x0, 2
    sw      x1,  4(x29)
    addi    x1,  x0, 8
    sw      x1,  8(x29)
    addi    x1,  x0, 1
    sw      x1,  12(x29)
    addi    x1,  x0, 4
    sw      x1,  16(x29)

    addi    x10, x0, 5

outer:
    addi    x12, x0, 0
    addi    x13, x0, 0
    addi    x14, x10, -1

inner:
    bge     x13, x14, after_inner
    slli    x15, x13, 2
    add     x16, x29, x15
    lw      x17, 0(x16)
    lw      x18, 4(x16)
    bge     x18, x17, no_swap
    sw      x18, 0(x16)
    sw      x17, 4(x16)
    addi    x12, x0, 1
no_swap:
    addi    x13, x13, 1
    jal     x0,  inner

after_inner:
    beq     x12, x0, done
    addi    x10, x10, -1
    jal     x0,  outer

done:
    lw      x1,  0(x29)
    addi    x2,  x0, 1
    bne     x1,  x2, fail
    lw      x1,  4(x29)
    addi    x2,  x0, 2
    bne     x1,  x2, fail
    lw      x1,  8(x29)
    addi    x2,  x0, 4
    bne     x1,  x2, fail
    lw      x1,  12(x29)
    addi    x2,  x0, 5
    bne     x1,  x2, fail
    lw      x1,  16(x29)
    addi    x2,  x0, 8
    bne     x1,  x2, fail
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
