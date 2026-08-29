.section .text
.globl _start
_start:
    lui     x30, 0x10000

    lui     x1,  0x12345
    auipc   x2,  0

    jal     x3,  after_jal
    jal     x0,  fail
after_jal:
    addi    x11, x0, 1

    addi    x5,  x0, 0x24
    jalr    x4,  0(x5)
    jal     x0,  fail
jalr_target:
    addi    x12, x0, 1

    lui     x6,  0x12345
    bne     x1,  x6, fail
    addi    x6,  x0, 8
    bne     x2,  x6, fail
    addi    x6,  x0, 16
    bne     x3,  x6, fail
    addi    x6,  x0, 32
    bne     x4,  x6, fail
    addi    x6,  x0, 1
    bne     x11, x6, fail
    bne     x12, x6, fail
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
