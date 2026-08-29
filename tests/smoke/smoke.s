.section .text
.globl _start
_start:
    lui     x30, 0x10000

    addi    x1,  x0, 2
    addi    x2,  x0, 3
    add     x3,  x1, x2

    addi    x4,  x0, 5
    bne     x3,  x4, fail
    jal     x0,  pass

pass:
    addi    x1,  x0, 1
    sw      x1,  0(x30)
    jal     x0, hang

fail:
    addi    x1,  x0, 2
    sw      x1,  0(x30)

hang:
    jal     x0, hang
