# ------------------------------------------------------------
# branch_alu_forward_focus.s - ALU results consumed by branch
#
# Expected:
#   DMEM[0] = 1
#   DMEM[4] = 3
#
# Halt: DMEM[0x3C] <- 1
# ------------------------------------------------------------

.section .text
.globl _start
_start:
    addi    x1,  x0, 5
    addi    x2,  x1, 0
    bge     x2,  x1, branch_taken

wrong_path:
    addi    x3,  x0, 2
    sw      x3,  0(x0)
    jal     x0,  after_branch

branch_taken:
    addi    x3,  x0, 1
    sw      x3,  0(x0)

after_branch:
    addi    x4,  x0, 3
    sw      x4,  4(x0)

    addi    x31, x0, 1
    sw      x31, 0x3C(x0)

hang:
    jal     x0, hang
