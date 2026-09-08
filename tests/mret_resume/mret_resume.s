.section .text
.globl _start
_start:
    lui     x30, 0x10000
    lui     x1,  %hi(after_mret)
    addi    x1,  x1, %lo(after_mret)
    csrw    mepc, x1

    mret

fail:
    addi    x1, x0, 2
    sw      x1, 0(x30)
    jal     x0, hang

after_mret:
    addi    x1, x0, 1
    sw      x1, 0(x30)

hang:
    jal     x0, hang
