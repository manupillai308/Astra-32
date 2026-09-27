.section .text
.globl _start
_start:
    lui     x30, 0x10000

    lui     x1, %hi(trap_handler)
    addi    x1, x1, %lo(trap_handler)
    csrw    mtvec, x1

    lui     x1, %hi(supervisor_entry)
    addi    x1, x1, %lo(supervisor_entry)
    csrw    sepc, x1

    # SPP=S and SPIE=1. SRET must enter S-mode, copy SPIE to SIE,
    # leave SPIE set, and clear SPP to U.
    addi    x1, x0, 0x120
    csrw    mstatus, x1
    sret

supervisor_entry:
    # This M-mode CSR access proves that SRET did not remain in M-mode.
    addi    x31, x0, 1
supervisor_illegal_access:
    csrr    x5, mstatus

    addi    x31, x0, 5
    jal     x0, fail

trap_handler:
    csrr    x6, mcause
    addi    x7, x0, 2
    bne     x6, x7, fail

    addi    x31, x0, 2
    csrr    x6, mtval
    lui     x7, 0x30002
    addi    x7, x7, 0x2f3
    bne     x6, x7, fail

    addi    x31, x0, 3
    csrr    x6, mepc
    lui     x7, %hi(supervisor_illegal_access)
    addi    x7, x7, %lo(supervisor_illegal_access)
    bne     x6, x7, fail

    # After SRET then M-mode trap entry: MPP=S, SIE=1, SPIE=1,
    # SPP=0, MIE=0, and MPIE=0.
    addi    x31, x0, 4
    csrr    x6, mstatus
    lui     x7, 0x1
    addi    x7, x7, -2048
    addi    x8, x0, 0x22
    or      x7, x7, x8
    bne     x6, x7, fail

pass:
    addi    x31, x0, 0
    addi    x1, x0, 1
    sw      x1, 0(x30)
    jal     x0, hang

fail:
    addi    x1, x0, 2
    sw      x1, 0(x30)

hang:
    jal     x0, hang
