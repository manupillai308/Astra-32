# ------------------------------------------------------------
# load_to_alu_focus.s - load result consumed by ALU ops
#
# Expected:
#   x2 = 7
#   x3 = 10
#   x4 = 14
#   DMEM[4] = 10
#
# Halt: DMEM[0x3C] <- 1
# ------------------------------------------------------------

.section .text
.globl _start
_start:
    addi    x1,  x0, 7
    sw      x1,  0(x0)

    lw      x2,  0(x0)
    addi    x3,  x2, 3
    add     x4,  x2, x2
    sw      x3,  4(x0)

    addi    x31, x0, 1
    sw      x31, 0x3C(x0)

hang:
    jal     x0, hang
