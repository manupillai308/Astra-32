.section .text
.globl _start
_start:
    lui     x10, 0x02000       # CLINT base: 0x0200_0000
    lui     x30, 0x10000       # LED MMIO:  0x1000_0000

    # Keep interrupts disabled. This test only checks whether a CSR read
    # observes the completed side effect of an older MMIO store.
    addi    x2, x0, 1
    sw      x2, 0(x10)         # Set CLINT MSIP.

    csrr    x3, mip            # Must observe MSIP after the store completes.
    andi    x3, x3, 0x8
    beq     x3, x0, fail

    sw      x0, 0(x10)         # Clear MSIP before reporting success.
    addi    x1, x0, 1
    sw      x1, 0(x30)

hang:
    jal     x0, hang

fail:
    sw      x0, 0(x10)
    addi    x1, x0, 2
    sw      x1, 0(x30)
    jal     x0, hang
