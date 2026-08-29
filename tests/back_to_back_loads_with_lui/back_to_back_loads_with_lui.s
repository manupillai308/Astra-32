.section .text
.globl _start
_start:
    lui     x30, 0x10000

    lui     x5,  0x12345
    addi    x6,  x5, 1
    addi    x7,  x6, 1

    lui     x8,  0x12345
    bne     x5,  x8, fail
    addi    x8,  x8, 1
    bne     x6,  x8, fail
    addi    x8,  x8, 1
    bne     x7,  x8, fail
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
