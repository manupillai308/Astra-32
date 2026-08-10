# ------------------------------------------------------------
# store_half_focus.s - isolate sb + sh behavior under dmem stalls
#
# Halt: DMEM[0x3C] <- 1
# ------------------------------------------------------------

.section .text
.globl _start
_start:
    addi    x1,  x0, -1         # x1 = 0xffffffff

    sb      x1,  0(x0)          # DMEM[0] = 0xff
    sh      x1,  2(x0)          # DMEM[2..3] = 0xffff

    lb      x2,  0(x0)          # signed byte   -> 0xffffffff
    lh      x3,  2(x0)          # signed half   -> 0xffffffff
    lhu     x4,  2(x0)          # unsigned half -> 0x0000ffff

    addi    x31, x0, 1
    sw      x31, 0x3C(x0)

hang:
    jal     x0,  hang
