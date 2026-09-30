.section .text
.globl _start
_start:
    lui     x30, 0x10000

    lui     x1, %hi(machine_handler)
    addi    x1, x1, %lo(machine_handler)
    csrw    mtvec, x1

    # mcounteren denies all lower-privilege counter accesses.
    csrw    mcounteren, x0
    lui     x1, %hi(supervisor_entry)
    addi    x1, x1, %lo(supervisor_entry)
    csrw    mepc, x1
    addi    x1, x0, 1
    slli    x1, x1, 11       # MPP=S
    csrw    mstatus, x1
    addi    x31, x0, 1
    mret

supervisor_entry:
denied_counter_access:
    csrr    x1, time
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
