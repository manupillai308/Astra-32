# ------------------------------------------------------------
# store_load_same_addr_focus.s - store followed by load same address
#
# Expected:
#   x2 = 21
#   x4 = 33
#   DMEM[0] = 33
#
# Halt: DMEM[0x3C] <- 1
# ------------------------------------------------------------

.section .text
.globl _start
_start:
    addi    x1,  x0, 21
    sw      x1,  0(x0)
    lw      x2,  0(x0)

    addi    x3,  x0, 33
    sw      x3,  0(x0)
    lw      x4,  0(x0)

    addi    x31, x0, 1
    sw      x31, 0x3C(x0)

hang:
    jal     x0, hang
