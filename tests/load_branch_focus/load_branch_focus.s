# ------------------------------------------------------------
# load_branch_focus.s - isolate load result forwarding into branch
#
# arr[0] = 5, arr[1] = 2
# bge x18, x17 should NOT be taken because 2 < 5.
#
# Correct path: DMEM[8] = 1
# Wrong path:   DMEM[8] = 2
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

    lw      x17, 0(x0)
    lw      x18, 4(x0)
    bge     x18, x17, wrong_path

    addi    x2,  x0, 1
    sw      x2,  8(x0)
    jal     x0,  done

wrong_path:
    addi    x2,  x0, 2
    sw      x2,  8(x0)

done:
    addi    x31, x0, 1
    sw      x31, 0x3C(x0)

hang:
    jal     x0,  hang
