.section .text
.globl _start
_start:
    lui     x29, 0x80000
    addi    x29, x29, 1
    lui     x30, 0x10000

    lui     x1, %hi(trap_handler)
    addi    x1, x1, %lo(trap_handler)
    csrw    mtvec, x1
    addi    x28, x0, 0

    addi    x31, x0, 1
    lr.w    x2, (x29)

    addi    x31, x0, 2
    addi    x3, x0, 7
    amoadd.w x4, x3, (x29)

    addi    x5, x0, 2
    bne     x28, x5, fail
    addi    x1, x0, 1
    sw      x1, 0(x30)
    jal     x0, hang

trap_handler:
    addi    x28, x28, 1
    csrr    x5, mtval
    bne     x5, x29, fail

    csrr    x5, mcause
    addi    x6, x0, 1
    beq     x31, x6, check_lr

    addi    x6, x0, 2
    bne     x31, x6, fail
    addi    x6, x0, 6
    bne     x5, x6, fail
    jal     x0, resume

check_lr:
    addi    x6, x0, 4
    bne     x5, x6, fail

resume:
    csrr    x5, mepc
    addi    x5, x5, 4
    csrw    mepc, x5
    mret

fail:
    addi    x1, x0, 2
    sw      x1, 0(x30)

hang:
    jal     x0, hang
