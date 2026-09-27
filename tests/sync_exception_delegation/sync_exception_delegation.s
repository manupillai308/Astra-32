.section .text
.globl _start
_start:
    lui     x30, 0x10000

    lui     x1, %hi(machine_handler)
    addi    x1, x1, %lo(machine_handler)
    csrw    mtvec, x1

    lui     x1, %hi(supervisor_handler)
    addi    x1, x1, %lo(supervisor_handler)
    csrw    stvec, x1

    # Delegate only U-mode ECALL (cause 8) to S-mode.
    addi    x1, x0, 0x100
    csrw    medeleg, x1

    lui     x1, %hi(user_entry)
    addi    x1, x1, %lo(user_entry)
    csrw    mepc, x1
    csrw    mstatus, x0
    mret

user_entry:
    addi    x20, x0, 1
    addi    x31, x0, 1
user_ecall:
    ecall

after_ecall:
    # SRET must return to U. This S-mode CSR access is therefore illegal,
    # and cause 2 is not delegated, so it must enter the M-mode handler.
    addi    x20, x0, 2
    addi    x31, x0, 5
user_illegal_access:
    csrr    x5, sstatus

    addi    x31, x0, 9
    jal     x0, fail

supervisor_handler:
    addi    x31, x0, 2
    csrr    x6, scause
    addi    x7, x0, 8
    bne     x6, x7, fail

    addi    x31, x0, 3
    csrr    x6, stval
    bne     x6, x0, fail

    addi    x31, x0, 4
    csrr    x6, sepc
    lui     x7, %hi(user_ecall)
    addi    x7, x7, %lo(user_ecall)
    bne     x6, x7, fail

    lui     x6, %hi(after_ecall)
    addi    x6, x6, %lo(after_ecall)
    csrw    sepc, x6
    sret

machine_handler:
    # Reaching M directly from the delegated ECALL is a routing failure.
    addi    x6, x0, 2
    bne     x20, x6, fail

    csrr    x6, mcause
    addi    x7, x0, 2
    bne     x6, x7, fail

    addi    x31, x0, 6
    csrr    x6, mtval
    lui     x7, 0x10002
    addi    x7, x7, 0x2f3
    bne     x6, x7, fail

    addi    x31, x0, 7
    csrr    x6, mepc
    lui     x7, %hi(user_illegal_access)
    addi    x7, x7, %lo(user_illegal_access)
    bne     x6, x7, fail

    # The later M-mode trap must not overwrite the delegated S trap bank.
    addi    x31, x0, 8
    csrr    x6, scause
    addi    x7, x0, 8
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
