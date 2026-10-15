.section .text
.globl _start
_start:
    lui     x20, 0x80000
    lui     x22, 0x80002
    lui     x30, 0x10000

    # User RWAD mapping for data and supervisor mapping for LED reporting.
    lui     x1, 0x20000
    ori     x1, x1, 0x0d7       # V | R | W | U | A | D
    sw      x1, 0x400(x20)
    lui     x1, 0x04000
    ori     x1, x1, 0x0c7
    sw      x1, 0x100(x20)

    addi    x2, x0, 0x45
    sw      x2, 0(x22)

    lui     x1, %hi(supervisor_handler)
    addi    x1, x1, %lo(supervisor_handler)
    csrw    stvec, x1
    addi    x1, x0, 0x100       # Delegate U-mode ecall, cause 8.
    csrw    medeleg, x1

    lui     x1, 0x80080
    csrw    satp, x1
    lui     x1, %hi(user_entry)
    addi    x1, x1, %lo(user_entry)
    csrw    mepc, x1
    csrw    mstatus, x0
    mret

user_entry:
    lui     x10, 0x40002
    lw      x3, 0(x10)
    bne     x3, x2, user_fail
    addi    x28, x0, 1
    ecall

user_fail:
    addi    x28, x0, 2
    ecall

supervisor_handler:
    addi    x31, x0, 1
    csrr    x3, scause
    addi    x4, x0, 8
    bne     x3, x4, fail
    addi    x4, x0, 1
    bne     x28, x4, fail

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
