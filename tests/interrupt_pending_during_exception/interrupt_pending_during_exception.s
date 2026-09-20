.section .text
.globl _start
_start:
    # LED MMIO reports the final self-test result: 1=pass, 2=fail.
    # RAM stores the phase committed by each trap handler.
    lui     x29, 0x80000
    lui     x30, 0x10000

    # Both the synchronous exception and timer interrupt use this handler.
    lui     x1, %hi(trap_handler)
    addi    x1, x1, %lo(trap_handler)
    csrw    mtvec, x1

    # Phase 0: waiting for ecall. Phase 1: ecall handler completed.
    # Phase 2: timer handler completed.
    sw      x0, 0(x29)

    # Enable MTI locally and machine interrupts globally. mtimecmp still
    # holds its reset value, so no interrupt is pending yet.
    addi    x1, x0, 0x80
    csrs    mie, x1
    addi    x1, x0, 0x8
    csrs    mstatus, x1

    # Trap synchronously while machine interrupts are enabled.
    ecall

after_ecall:
    # The timer handler must have committed phase 2 before execution resumes.
    lw      x2, 0(x29)
    addi    x1, x0, 2
    bne     x2, x1, fail

    addi    x1, x0, 1
    sw      x1, 0(x30)
    jal     x0, hang

trap_handler:
    csrr    x2, mcause
    blt     x2, x0, timer_handler

ecall_handler:
    # The first trap must be the synchronous machine-mode ecall.
    addi    x3, x0, 11
    bne     x2, x3, fail
    lw      x4, 0(x29)
    bne     x4, x0, fail

    # Trap entry must disable MIE while preserving its old value in MPIE.
    csrr    x3, mstatus
    andi    x4, x3, 0x8
    bne     x4, x0, fail
    andi    x4, x3, 0x80
    beq     x4, x0, fail

    # Arm the timer while still inside the synchronous exception handler.
    # MTIME is read through -8/-4 offsets from 0x0200_C000.
    lui     x10, 0x0200c
    lw      x11, -8(x10)
    lw      x12, -4(x10)
    addi    x13, x11, 128
    sltu    x14, x13, x11
    add     x14, x12, x14

    # RV32-safe update of the 64-bit mtimecmp register.
    lui     x10, 0x02004
    addi    x15, x0, -1
    sw      x15, 0(x10)
    sw      x14, 4(x10)
    sw      x13, 0(x10)

wait_for_mtip:
    # MTIP must become pending, but MIE=0 must prevent it from preempting
    # this synchronous exception handler.
    csrr    x3, mip
    andi    x3, x3, 0x80
    beq     x3, x0, wait_for_mtip

    # Commit phase 1 before returning. The timer handler must observe it.
    addi    x4, x0, 1
    sw      x4, 0(x29)

    # Resume after ecall. mret restores MIE from MPIE, making the already
    # pending timer interrupt eligible immediately after the return.
    csrr    x3, mepc
    addi    x3, x3, 4
    csrw    mepc, x3
    mret

timer_handler:
    # The timer interrupt must observe the ecall handler's committed write.
    lw      x4, 0(x29)
    addi    x3, x0, 1
    bne     x4, x3, fail

    lui     x3, 0x80000
    addi    x3, x3, 7
    bne     x2, x3, fail

    # Clear MTIP before returning from the interrupt.
    lui     x10, 0x02004
    addi    x15, x0, -1
    sw      x15, 0(x10)
    sw      x15, 4(x10)

    # Increment and commit phase 2 before returning to normal execution.
    addi    x4, x4, 1
    sw      x4, 0(x29)
    mret

fail:
    addi    x1, x0, 2
    sw      x1, 0(x30)

hang:
    jal     x0, hang
