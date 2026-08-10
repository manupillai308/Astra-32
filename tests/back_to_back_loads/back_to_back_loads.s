# ------------------------------------------------------------
# back_to_back_loads.s - isolate consecutive delayed RAM loads
#
# Expected:
#   DMEM[0] = 5
#   DMEM[4] = 2
#   x2      = 5
#   x3      = 2
#
# Halt: DMEM[0x3C] <- 1
# ------------------------------------------------------------

.section .text
.globl _start
_start:
    addi    x1,  x0, 5
    sw      x1,  0(x0)

    addi    x1,  x0, 2
    sw      x1,  4(x0)

    lw      x2,  0(x0)
    lw      x3,  4(x0)

    addi    x31, x0, 1
    sw      x31, 0x3C(x0)

hang:
    jal     x0,  hang
