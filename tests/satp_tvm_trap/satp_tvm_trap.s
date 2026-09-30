.section .text
.globl _start
_start:
    lui     x30, 0x10000

    lui     x1, %hi(machine_handler)
    addi    x1, x1, %lo(machine_handler)
    csrw    mtvec, x1

    lui     x1, %hi(supervisor_entry)
    addi    x1, x1, %lo(supervisor_entry)
    csrw    mepc, x1

    # Enter S-mode with TVM set.
    lui     x1, 0x101
    addi    x1, x1, -2048     # TVM | MPP=S
    csrw    mstatus, x1
    addi    x31, x0, 1
    mret

supervisor_entry:
blocked_satp_access:
    csrr    x1, satp
    jal     x0, fail

machine_handler:
    addi    x31, x0, 2
    csrr    x2, mcause
    addi    x3, x0, 2
    bne     x2, x3, fail

    addi    x31, x0, 3
    csrr    x2, mepc
    lui     x3, %hi(blocked_satp_access)
    addi    x3, x3, %lo(blocked_satp_access)
    bne     x2, x3, fail

    addi    x31, x0, 0
    addi    x1, x0, 1
    sw      x1, 0(x30)
    jal     x0, hang

fail:
    addi    x1, x0, 2
    sw      x1, 0(x30)

hang:
    jal     x0, hang
