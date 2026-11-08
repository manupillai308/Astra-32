.section .text
.globl _start
_start:
    lui     x30, 0x10000       # LED MMIO:   0x1000_0000
    lui     x10, 0x02000       # CLINT MSIP: 0x0200_0000

    lui     x1, %hi(trap_handler)
    addi    x1, x1, %lo(trap_handler)
    csrw    mtvec, x1

    addi    x28, x0, 0         # Number of interrupts serviced.

    # Enable MSI and STI locally while global MIE remains clear.
    addi    x1, x0, 40         # mip/mie bits 3 and 5.
    csrw    mie, x1

    # Make both interrupts pending before either can be taken.
    addi    x2, x0, 32
    csrw    mip, x2            # Set software-injected STIP.
    addi    x2, x0, 1
    sw      x2, 0(x10)         # Set CLINT MSIP.

    # Enabling MIE must select MSI before STI.
    addi    x1, x0, 8
    csrs    mstatus, x1

resume_point:
    # Neither pending interrupt may remain when normal execution resumes.
    addi    x1, x0, 2
    bne     x28, x1, fail_resume_count
    csrr    x2, mip
    andi    x2, x2, 40
    bne     x2, x0, fail_pending_after_resume

    addi    x1, x0, 1
    sw      x1, 0(x30)
    jal     x0, hang

trap_handler:
    beq     x28, x0, first_interrupt
    addi    x1, x0, 1
    beq     x28, x1, second_interrupt
    jal     x0, fail_extra_interrupt

first_interrupt:
    # MSI has priority over STI in the implemented fixed-priority order.
    csrr    x2, mcause
    lui     x3, 0x80000
    addi    x3, x3, 3
    bne     x2, x3, fail_first_cause

    # Both sources must still be visible until MSI is acknowledged.
    csrr    x2, mip
    andi    x2, x2, 40
    addi    x3, x0, 40
    bne     x2, x3, fail_first_pending

    csrr    x2, mepc
    lui     x3, %hi(resume_point)
    addi    x3, x3, %lo(resume_point)
    bne     x2, x3, fail_first_mepc

    sw      x0, 0(x10)         # Clear MSI, leaving STI pending.
    addi    x28, x0, 1
    mret

second_interrupt:
    # The still-pending STI must be taken before resume_point executes.
    csrr    x2, mcause
    lui     x3, 0x80000
    addi    x3, x3, 5
    bne     x2, x3, fail_second_cause

    csrr    x2, mip
    andi    x2, x2, 40
    addi    x3, x0, 32
    bne     x2, x3, fail_second_pending

    csrr    x2, mepc
    lui     x3, %hi(resume_point)
    addi    x3, x3, %lo(resume_point)
    bne     x2, x3, fail_second_mepc

    csrw    mip, x0            # Clear software-injected STIP.
    addi    x28, x0, 2
    mret

fail_first_cause:
    addi    x31, x0, 1
    jal     x0, fail
fail_first_pending:
    addi    x31, x0, 2
    jal     x0, fail
fail_first_mepc:
    addi    x31, x0, 3
    jal     x0, fail
fail_second_cause:
    addi    x31, x0, 4
    jal     x0, fail
fail_second_pending:
    addi    x31, x0, 5
    jal     x0, fail
fail_second_mepc:
    addi    x31, x0, 6
    jal     x0, fail
fail_extra_interrupt:
    addi    x31, x0, 7
    jal     x0, fail
fail_resume_count:
    addi    x31, x0, 8
    jal     x0, fail
fail_pending_after_resume:
    addi    x31, x0, 9

fail:
    sw      x0, 0(x10)
    csrw    mip, x0
    addi    x1, x0, 2
    sw      x1, 0(x30)

hang:
    jal     x0, hang
