# ------------------------------------------------------------
# load_to_store_data_focus.s - load result used as store data
#
# Expected:
#   DMEM[0] = 9
#   DMEM[4] = 9
#   x3 = 9
#
# Halt: DMEM[0x3C] <- 1
# ------------------------------------------------------------

.section .text
.globl _start
_start:
    addi    x1,  x0, 9
    sw      x1,  0(x0)

    lw      x2,  0(x0)
    sw      x2,  4(x0)
    lw      x3,  4(x0)

    addi    x31, x0, 1
    sw      x31, 0x3C(x0)

hang:
    jal     x0, hang
