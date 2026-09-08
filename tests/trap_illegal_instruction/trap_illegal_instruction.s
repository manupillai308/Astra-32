.section .text
.globl _start
_start:
    lui     x30, 0x10000
    lui     x1,  %hi(trap_handler)
    addi    x1,  x1, %lo(trap_handler)
    csrw    mtvec, x1

    .word   0xffffffff

after_trap:
    addi    x1, x0, 1
    sw      x1, 0(x30)
    jal     x0, hang

trap_handler:
    csrr    x2, mcause
    addi    x3, x0, 2
    bne     x2, x3, fail

    csrr    x2, mtval
    addi    x3, x0, -1
    bne     x2, x3, fail

    csrr    x2, mepc
    addi    x2, x2, 4
    csrw    mepc, x2
    mret

fail:
    addi    x1, x0, 2
    sw      x1, 0(x30)

hang:
    jal     x0, hang
