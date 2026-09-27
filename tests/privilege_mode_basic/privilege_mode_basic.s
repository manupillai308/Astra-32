.section .text
.globl _start
_start:
    lui     x30, 0x10000

    lui     x1, %hi(trap_handler)
    addi    x1, x1, %lo(trap_handler)
    csrw    mtvec, x1

    lui     x1, %hi(supervisor_entry)
    addi    x1, x1, %lo(supervisor_entry)
    csrw    mepc, x1

    # Enter S-mode through mret with MPP=S.
    lui     x1, 0x1
    addi    x1, x1, -2048
    csrw    mstatus, x1
    mret

supervisor_entry:
    # 1: S-mode must be allowed to read supervisor CSRs.
    addi    x31, x0, 1
    csrr    x4, sstatus

    # 2-3: S-mode access to an M-mode CSR must trap as illegal.
    addi    x20, x0, 1
    addi    x31, x0, 2
illegal_mstatus:
    csrr    x5, mstatus

after_illegal_mstatus:
    # 4-5: ECALL from S-mode must report cause 9 and mtval=0.
    addi    x20, x0, 2
    addi    x31, x0, 4
    ecall

after_ecall:
    # 6-7: mret itself must be illegal outside M-mode.
    addi    x20, x0, 3
    addi    x31, x0, 6
illegal_mret:
    mret

    addi    x31, x0, 8
    jal     x0, fail

trap_handler:
    addi    x6, x0, 1
    beq     x20, x6, check_illegal_mstatus
    addi    x6, x0, 2
    beq     x20, x6, check_supervisor_ecall
    addi    x6, x0, 3
    beq     x20, x6, check_illegal_mret
    jal     x0, fail

check_illegal_mstatus:
    csrr    x6, mcause
    addi    x7, x0, 2
    bne     x6, x7, fail

    addi    x31, x0, 3
    csrr    x6, mtval
    lui     x7, 0x30002
    addi    x7, x7, 0x2f3
    bne     x6, x7, fail

    lui     x6, %hi(after_illegal_mstatus)
    addi    x6, x6, %lo(after_illegal_mstatus)
    csrw    mepc, x6
    mret

check_supervisor_ecall:
    csrr    x6, mcause
    addi    x7, x0, 9
    bne     x6, x7, fail

    addi    x31, x0, 5
    csrr    x6, mtval
    bne     x6, x0, fail

    lui     x6, %hi(after_ecall)
    addi    x6, x6, %lo(after_ecall)
    csrw    mepc, x6
    mret

check_illegal_mret:
    csrr    x6, mcause
    addi    x7, x0, 2
    bne     x6, x7, fail

    addi    x31, x0, 7
    csrr    x6, mtval
    lui     x7, 0x30200
    addi    x7, x7, 0x73
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
