.section .text
.globl _start
_start:
    lui     x29, 0x80000
    lui     x30, 0x10000

    lui     x1,  %hi(target)
    addi    x1,  x1, %lo(target)
    sw      x1,  0(x29)
    lw      x2,  0(x29)
    jalr    x3,  0(x2)
    jal     x0,  fail

target:
    addi    x4,  x0, 1
    addi    x5,  x0, 1
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
