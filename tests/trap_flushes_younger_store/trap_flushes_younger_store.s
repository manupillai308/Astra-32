.section .text
.globl _start
_start:
    lui     x29, 0x80000
    lui     x30, 0x10000

    lui     x1,  %hi(trap_handler)
    addi    x1,  x1, %lo(trap_handler)
    csrw    mtvec, x1

    addi    x2,  x0, 1
    sw      x2,  0(x29)
    addi    x3,  x0, 2

    ecall
    sw      x3,  0(x29)

after_trap:
    lw      x4,  0(x29)
    bne     x4,  x2, fail

    addi    x1,  x0, 1
    sw      x1,  0(x30)
    jal     x0,  hang

trap_handler:
    csrr    x5,  mcause
    addi    x6,  x0, 11
    bne     x5,  x6, fail

    csrr    x5,  mepc
    addi    x5,  x5, 8
    csrw    mepc, x5
    mret

fail:
    addi    x1,  x0, 2
    sw      x1,  0(x30)

hang:
    jal     x0,  hang
