.section .text
.globl _start
_start:
    lui     x30, 0x10000

    lui     x1, %hi(machine_handler)
    addi    x1, x1, %lo(machine_handler)
    csrw    mtvec, x1

    # M-mode permits counter access, but S-mode denies it to U-mode.
    addi    x1, x0, 7
    csrw    mcounteren, x1
    csrw    scounteren, x0

    lui     x1, %hi(user_entry)
    addi    x1, x1, %lo(user_entry)
    csrw    mepc, x1
    csrw    mstatus, x0       # MPP=U
    addi    x31, x0, 1
    mret

user_entry:
denied_counter_access:
    csrr    x1, cycle
    jal     x0, fail

machine_handler:
    addi    x31, x0, 2
    csrr    x2, mcause
    addi    x3, x0, 2
    bne     x2, x3, fail

    addi    x31, x0, 3
    csrr    x2, mepc
    lui     x3, %hi(denied_counter_access)
    addi    x3, x3, %lo(denied_counter_access)
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
