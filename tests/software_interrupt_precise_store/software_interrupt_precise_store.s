.section .text
.globl _start
_start:
    # RAM holds a sentinel used to detect an incorrectly committed store.
    # LED MMIO reports the final result: 1=pass, 2=fail.
    lui     x29, 0x80000
    lui     x30, 0x10000

    # Install a direct-mode machine trap handler.
    lui     x1, %hi(trap_handler)
    addi    x1, x1, %lo(trap_handler)
    csrw    mtvec, x1

    addi    x2, x0, 1
    sw      x2, 0(x29)
    addi    x3, x0, 2

    # Enable machine software interrupts locally and globally while MSIP
    # is still clear.
    addi    x1, x0, 0x8
    csrs    mie, x1
    csrs    mstatus, x1

    # Set CLINT MSIP at 0x0200_0000. This MMIO store is older than the
    # RAM store immediately following it and is allowed to complete.
    lui     x10, 0x02000
    sw      x2, 0(x10)

younger_store:
    # Interrupt entry must squash this store before it reaches memory.
    sw      x3, 0(x29)

fail:
    addi    x1, x0, 2
    sw      x1, 0(x30)
    jal     x0, hang

trap_handler:
    # Machine software interrupt: asynchronous bit 31 plus cause code 3.
    csrr    x4, mcause
    lui     x5, 0x80000
    addi    x5, x5, 3
    bne     x4, x5, fail

    # The architectural resume PC must identify the first instruction that
    # did not retire: the younger RAM store.
    csrr    x4, mepc
    lui     x5, %hi(younger_store)
    addi    x5, x5, %lo(younger_store)
    bne     x4, x5, fail

    # Clear the level-sensitive software interrupt before checking state.
    sw      x0, 0(x10)

    # The younger store must not have changed the original sentinel.
    lw      x4, 0(x29)
    bne     x4, x2, fail

    addi    x1, x0, 1
    sw      x1, 0(x30)

hang:
    jal     x0, hang
