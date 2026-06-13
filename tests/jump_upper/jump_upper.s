# ------------------------------------------------------------
# jump_upper.s - exercise LUI/AUIPC/JAL/JALR paths
#
# x10 remains zero unless a jump fails to skip its trap instruction.
#
# Expected:
#   x1 = 0x12345000 from LUI
#   x2 = 0x00000004 from AUIPC at PC 4 with imm 0
#   x3 = 0x0000000c from JAL link at PC 8
#   x4 = 0x0000001c from JALR link at PC 24
#
# Halt: DMEM[0x3C] <- 1
# ------------------------------------------------------------

.section .text
.globl _start
_start:
    lui     x1,  0x12345
    auipc   x2,  0

    jal     x3,  after_jal
    addi    x10, x0, 1
after_jal:
    addi    x11, x0, 1

    addi    x5,  x0, 0x20        # jalr_target address
    jalr    x4,  0(x5)
    addi    x10, x0, 2
jalr_target:
    addi    x12, x0, 1

    addi    x31, x0, 1
    sw      x31, 0x3C(x0)
hang:
    jal     x0,  hang
