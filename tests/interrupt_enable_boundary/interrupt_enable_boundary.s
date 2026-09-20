.section .text
.globl _start
_start:
    # RAM holds a sentinel used to detect a younger store retiring across
    # the interrupt-enable boundary. LED MMIO reports 1=pass and 2=fail.
    lui     x29, 0x80000
    lui     x30, 0x10000

    lui     x1, %hi(trap_handler)
    addi    x1, x1, %lo(trap_handler)
    csrw    mtvec, x1

    addi    x2, x0, 1
    sw      x2, 0(x29)
    addi    x3, x0, 2

    # Enable MSIP locally, but leave global mstatus.MIE clear.
    addi    x1, x0, 0x8
    csrs    mie, x1

    # Raise CLINT MSIP while global interrupts are disabled.
    lui     x10, 0x02000
    sw      x2, 0(x10)

    # Confirm that MSIP is architecturally visible before enabling MIE.
    csrr    x4, mip
    andi    x4, x4, 0x8
    beq     x4, x0, fail

    # The pending interrupt must be reevaluated immediately after this
    # explicit write to mstatus retires.
    csrs    mstatus, x1

younger_store:
    # This instruction may be fetched or processed speculatively, but it
    # must not retire or modify RAM before interrupt entry.
    sw      x3, 0(x29)

fail:
    addi    x1, x0, 2
    sw      x1, 0(x30)
    jal     x0, hang

trap_handler:
    # The accepted interrupt must be a machine software interrupt.
    csrr    x4, mcause
    lui     x5, 0x80000
    addi    x5, x5, 3
    bne     x4, x5, fail

    # The first instruction that did not retire must be the younger store.
    csrr    x4, mepc
    lui     x5, %hi(younger_store)
    addi    x5, x5, %lo(younger_store)
    bne     x4, x5, fail

    # Clear the level-sensitive interrupt before validating memory state.
    sw      x0, 0(x10)

    lw      x4, 0(x29)
    bne     x4, x2, fail

    addi    x1, x0, 1
    sw      x1, 0(x30)

hang:
    jal     x0, hang
