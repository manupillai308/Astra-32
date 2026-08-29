.section .text
.globl _start
_start:
    lui     x30, 0x10000

    addi    x1,  x0, 5
    addi    x2,  x1, 0
    bge     x2,  x1, branch_taken
    jal     x0,  fail

branch_taken:
    addi    x3,  x0, 1
    addi    x4,  x0, 3
    addi    x5,  x0, 1
    bne     x3,  x5, fail
    addi    x5,  x0, 3
    bne     x4,  x5, fail
    jal     x0,  pass

pass:
    addi    x1,  x0, 1
    sw      x1,  0(x30)
    jal     x0,  hang

fail:
    addi    x1,  x0, 2
    sw      x1,  0(x30)

hang:
    jal     x0, hang
