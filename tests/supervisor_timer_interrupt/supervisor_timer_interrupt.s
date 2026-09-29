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

    # Delegate, enable, and inject a supervisor timer interrupt.
    addi    x1, x0, 32
    csrw    mideleg, x1
    csrw    mie, x1
    csrw    mip, x1

    lui     x2, %hi(user_entry)
    addi    x2, x2, %lo(user_entry)
    csrw    mepc, x2
    csrw    mstatus, x0

    addi    x31, x0, 1
    mret

user_entry:
    # The pending delegated interrupt must be taken before this executes.
    jal     x0, fail

supervisor_handler:
    addi    x31, x0, 2
    csrr    x3, scause
    lui     x4, 0x80000
    addi    x4, x4, 5
    bne     x3, x4, fail

    addi    x31, x0, 3
    csrr    x3, sip
    andi    x3, x3, 32
    beq     x3, x0, fail

    # STIP is visible but read-only through sip.
    csrw    sip, x0
    csrr    x3, sip
    andi    x3, x3, 32
    beq     x3, x0, fail

    addi    x31, x0, 0
    addi    x1, x0, 1
    sw      x1, 0(x30)
    jal     x0, hang

machine_handler:
    # A delegated STI must not enter M-mode.
    jal     x0, fail

fail:
    addi    x1, x0, 2
    sw      x1, 0(x30)

hang:
    jal     x0, hang
