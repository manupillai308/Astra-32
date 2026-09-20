.section .text
.globl _start
_start:
    # LED MMIO reports the final self-test result: 1=pass, 2=fail.
    lui     x30, 0x10000

    # Install a direct-mode machine trap handler.
    lui     x1, %hi(trap_handler)
    addi    x1, x1, %lo(trap_handler)
    csrw    mtvec, x1

    # The handler sets this flag before mret so the interrupted loop exits.
    addi    x28, x0, 0

    # Enable machine timer interrupts locally and globally. MTIP is still
    # clear because mtimecmp resets to its maximum 64-bit value.
    addi    x1, x0, 0x80
    csrs    mie, x1
    addi    x1, x0, 0x8
    csrs    mstatus, x1

    # Read the 64-bit mtime value. MTIME_LO is 0x0200_BFF8 and MTIME_HI
    # is 0x0200_BFFC, addressed as -8 and -4 from 0x0200_C000.
    lui     x10, 0x0200c
    lw      x11, -8(x10)
    lw      x12, -4(x10)

    # Schedule the interrupt 256 timer ticks ahead and propagate a carry
    # from the low 32-bit addition into the high half.
    addi    x13, x11, 256
    sltu    x14, x13, x11
    add     x14, x12, x14

    # Program mtimecmp at 0x0200_4000 using the RV32-safe sequence:
    # low=-1, desired high, then desired low.
    lui     x10, 0x02004
    addi    x15, x0, -1
    sw      x15, 0(x10)
    sw      x14, 4(x10)
    sw      x13, 0(x10)

wait_for_interrupt:
    beq     x28, x0, wait_for_interrupt

    # Reaching here proves that mret resumed normal execution.
    addi    x1, x0, 1
    sw      x1, 0(x30)
    jal     x0, hang

trap_handler:
    # Machine timer interrupt: asynchronous bit 31 plus cause code 7.
    csrr    x2, mcause
    lui     x3, 0x80000
    addi    x3, x3, 7
    bne     x2, x3, fail

    # MTIP must remain visible through mip[7] until mtimecmp is moved.
    csrr    x2, mip
    andi    x2, x2, 0x80
    beq     x2, x0, fail

    # Clear MTIP by moving mtimecmp back to its maximum value.
    lui     x10, 0x02004
    addi    x15, x0, -1
    sw      x15, 0(x10)
    sw      x15, 4(x10)

    # Signal handler completion and return to the interrupted instruction.
    addi    x28, x0, 1
    mret

fail:
    addi    x1, x0, 2
    sw      x1, 0(x30)

hang:
    jal     x0, hang
