.section .text
.globl _start
_start:
    lui     x30, 0x10000

    addi    x1, x0, 5
    fence   rw, rw
    addi    x1, x1, 7

    addi    x2, x0, 12
    bne     x1, x2, fail

pass:
    addi    x1, x0, 1
    sw      x1, 0(x30)
    jal     x0, hang

fail:
    addi    x1, x0, 2
    sw      x1, 0(x30)

hang:
    jal     x0, hang
