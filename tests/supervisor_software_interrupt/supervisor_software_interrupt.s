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

    # Delegate and enable the supervisor software interrupt.
    addi    x1, x0, 2
    csrw    mideleg, x1
    csrw    mie, x1

    lui     x2, %hi(user_entry)
    addi    x2, x2, %lo(user_entry)
    csrw    mepc, x2
    csrw    mstatus, x0

    # Make SSIP pending while still in M-mode. A delegated S interrupt
    # cannot preempt M-mode, but must be taken after MRET enters U-mode.
    csrw    mip, x1
    addi    x31, x0, 1
    mret

user_entry:
    addi    x31, x0, 0
    addi    x1, x0, 1
    sw      x1, 0(x30)
    jal     x0, hang

supervisor_handler:
    addi    x31, x0, 2
    csrr    x3, scause
    lui     x4, 0x80000
    addi    x4, x4, 1
    bne     x3, x4, fail

    addi    x31, x0, 3
    csrr    x3, sepc
    lui     x4, %hi(user_entry)
    addi    x4, x4, %lo(user_entry)
    bne     x3, x4, fail

    addi    x31, x0, 4
    csrr    x3, sip
    andi    x3, x3, 2
    beq     x3, x0, fail

    # Acknowledge the level-sensitive source before returning to U-mode.
    csrw    sip, x0
    sret

machine_handler:
    # A delegated SSI must not enter M-mode.
    jal     x0, fail

fail:
    addi    x1, x0, 2
    sw      x1, 0(x30)

hang:
    jal     x0, hang
