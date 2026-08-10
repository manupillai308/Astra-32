# ------------------------------------------------------------
# mmio_after_ram_stall_focus.s - RAM stall next to MMIO accesses
#
# Expected:
#   DMEM[0] = 3
#   LED = 5
#   x3 = 3
#
# Halt: DMEM[0x3C] <- 1
# ------------------------------------------------------------

.section .text
.globl _start
_start:
    lui     x1,  0x10000          # MMIO base: 0x1000_0000

    addi    x2,  x0, 3
    sw      x2,  0(x0)
    lw      x3,  0(x0)

    addi    x4,  x0, 5
    sw      x4,  0(x1)            # LED MMIO

    addi    x31, x0, 1
    sw      x31, 0x3C(x0)

hang:
    jal     x0, hang
