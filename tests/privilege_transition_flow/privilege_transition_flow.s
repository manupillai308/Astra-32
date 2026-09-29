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

    # ECALLs from S-mode and U-mode are handled in S-mode.
    addi    x1, x0, 768
    csrw    medeleg, x1

    lui     x1, %hi(supervisor_entry)
    addi    x1, x1, %lo(supervisor_entry)
    csrw    mepc, x1

    # MPP=S, so MRET enters supervisor mode.
    addi    x1, x0, 1
    slli    x1, x1, 11
    csrw    mstatus, x1
    addi    x31, x0, 1
    mret

supervisor_entry:
    # Cause 9 proves that MRET actually selected S-mode.
    addi    x31, x0, 2
supervisor_ecall:
    ecall

supervisor_resume:
    addi    x31, x0, 3
    addi    x1, x0, 51
    bne     x21, x1, fail

    lui     x1, %hi(user_entry)
    addi    x1, x1, %lo(user_entry)
    csrw    sepc, x1
    csrw    sstatus, x0       # SPP=U
    sret

user_entry:
    addi    x31, x0, 4
user_ecall:
    ecall

user_resume:
    addi    x31, x0, 7
    addi    x1, x0, 85
    bne     x20, x1, fail

    addi    x31, x0, 0
    addi    x1, x0, 1
    sw      x1, 0(x30)
    jal     x0, hang

supervisor_handler:
    csrr    x2, scause
    addi    x3, x0, 9
    beq     x2, x3, supervisor_ecall_handler
    addi    x3, x0, 8
    beq     x2, x3, user_ecall_handler
    jal     x0, fail

supervisor_ecall_handler:
    addi    x31, x0, 5
    csrr    x2, sepc
    lui     x3, %hi(supervisor_ecall)
    addi    x3, x3, %lo(supervisor_ecall)
    bne     x2, x3, fail

    addi    x2, x2, 4
    csrw    sepc, x2
    addi    x21, x0, 51
    sret

user_ecall_handler:
    addi    x31, x0, 6
    csrr    x2, sepc
    lui     x3, %hi(user_ecall)
    addi    x3, x3, %lo(user_ecall)
    bne     x2, x3, fail

    # ECALL does not advance xepc. Skip it before returning to U-mode.
    addi    x2, x2, 4
    csrw    sepc, x2
    addi    x20, x0, 85
    sret

machine_handler:
    # Both expected ECALLs are delegated, so any M-mode trap is a failure.
    addi    x31, x0, 8

fail:
    addi    x1, x0, 2
    sw      x1, 0(x30)

hang:
    jal     x0, hang
