# ------------------------------------------------------------
# store_forward_sequence.s - isolate addi-to-store forwarding
#
# Mirrors the bubble_sort initialization pattern:
#   addi x1, imm
#   sw   x1, offset
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

    addi    x1,  x0, 8
    sw      x1,  8(x0)

    addi    x1,  x0, 1
    sw      x1,  12(x0)

    addi    x1,  x0, 4
    sw      x1,  16(x0)

    lw      x2,  0(x0)
    lw      x3,  4(x0)
    lw      x4,  8(x0)
    lw      x5,  12(x0)
    lw      x6,  16(x0)

    addi    x31, x0, 1
    sw      x31, 0x3C(x0)

hang:
    jal     x0,  hang
