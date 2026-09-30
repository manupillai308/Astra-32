.section .text
.globl _start
_start:
    lui     x30, 0x10000

    lui     x1, %hi(unexpected_trap)
    addi    x1, x1, %lo(unexpected_trap)
    csrw    mtvec, x1

    addi    x1, x0, 7
    csrw    mcounteren, x1
    lui     x1, %hi(supervisor_entry)
    addi    x1, x1, %lo(supervisor_entry)
    csrw    mepc, x1
    addi    x1, x0, 1
    slli    x1, x1, 11       # MPP=S
    csrw    mstatus, x1
    addi    x31, x0, 1
    mret

supervisor_entry:
    addi    x31, x0, 2
    csrr    x1, cycle
    csrr    x2, time
    csrr    x3, instret
    csrr    x4, cycleh
    csrr    x5, timeh
    csrr    x6, instreth

    addi    x31, x0, 0
    addi    x1, x0, 1
    sw      x1, 0(x30)
    jal     x0, hang

unexpected_trap:
fail:
    addi    x1, x0, 2
    sw      x1, 0(x30)

hang:
    jal     x0, hang
