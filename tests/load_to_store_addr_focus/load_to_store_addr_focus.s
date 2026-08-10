# ------------------------------------------------------------
# load_to_store_addr_focus.s - load result used as store address
#
# Expected:
#   DMEM[0]  = 16
#   DMEM[16] = 11
#   x4 = 11
#
# Halt: DMEM[0x3C] <- 1
# ------------------------------------------------------------

.section .text
.globl _start
_start:
    addi    x1,  x0, 16
    sw      x1,  0(x0)

    addi    x2,  x0, 11
    lw      x3,  0(x0)
    sw      x2,  0(x3)
    lw      x4,  16(x0)

    addi    x31, x0, 1
    sw      x31, 0x3C(x0)

hang:
    jal     x0, hang
