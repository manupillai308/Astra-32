# ------------------------------------------------------------
# bubble_swap_focus.s - isolate bubble-sort compare/swap pattern
#
# Starts with [5, 2]. The pair must swap to [2, 5].
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

    addi    x15, x0, 0          # offset = 0
    lw      x17, 0(x15)         # a = arr[0]
    lw      x18, 4(x15)         # b = arr[1]
    bge     x18, x17, no_swap   # if b >= a, leave unchanged
    sw      x18, 0(x15)         # arr[0] = b
    sw      x17, 4(x15)         # arr[1] = a

no_swap:
    lw      x2,  0(x0)
    lw      x3,  4(x0)

    addi    x31, x0, 1
    sw      x31, 0x3C(x0)

hang:
    jal     x0,  hang
