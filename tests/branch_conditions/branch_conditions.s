# ------------------------------------------------------------
# branch_conditions.s - exercise all RV32I branch funct3 cases
#
# x10 remains zero unless a branch fails.
# x11 counts successful branch cases and should finish as 6.
#
# Halt: DMEM[0x3C] <- 1
# ------------------------------------------------------------

.section .text
.globl _start
_start:
    addi    x1,  x0, 5
    addi    x2,  x0, 5
    addi    x3,  x0, 7
    addi    x4,  x0, -1
    addi    x5,  x0, 1
    addi    x11, x0, 0

    beq     x1,  x2, beq_ok
    addi    x10, x0, 1
beq_ok:
    addi    x11, x11, 1

    bne     x1,  x3, bne_ok
    addi    x10, x0, 2
bne_ok:
    addi    x11, x11, 1

    blt     x4,  x5, blt_ok    # signed: -1 < 1
    addi    x10, x0, 3
blt_ok:
    addi    x11, x11, 1

    bge     x5,  x4, bge_ok    # signed: 1 >= -1
    addi    x10, x0, 4
bge_ok:
    addi    x11, x11, 1

    bltu    x5,  x4, bltu_ok   # unsigned: 1 < 0xffffffff
    addi    x10, x0, 5
bltu_ok:
    addi    x11, x11, 1

    bgeu    x4,  x5, bgeu_ok   # unsigned: 0xffffffff >= 1
    addi    x10, x0, 6
bgeu_ok:
    addi    x11, x11, 1

    addi    x31, x0, 1
    sw      x31, 0x3C(x0)
hang:
    jal     x0,  hang
