# ------------------------------------------------------------
# load_store_width.s - exercise byte/halfword/word memory paths
#
# Covers:
#   sb, sh, sw
#   lb, lh, lw, lbu, lhu
#
# Halt: DMEM[0x3C] <- 1
# ------------------------------------------------------------

.section .text
.globl _start
_start:
    addi    x1,  x0, -1         # x1 = 0xffffffff

    sb      x1,  0(x0)          # DMEM[0] = 0xff
    sh      x1,  2(x0)          # DMEM[2..3] = 0xffff
    sw      x1,  4(x0)          # DMEM[4..7] = 0xffffffff

    lb      x2,  0(x0)          # signed byte   -> 0xffffffff
    lbu     x3,  0(x0)          # unsigned byte -> 0x000000ff
    lh      x4,  2(x0)          # signed half   -> 0xffffffff
    lhu     x5,  2(x0)          # unsigned half -> 0x0000ffff
    lw      x6,  4(x0)          # word          -> 0xffffffff

    addi    x7,  x0, 0x12
    sb      x7,  8(x0)
    lb      x8,  8(x0)          # positive signed byte -> 0x12

    addi    x31, x0, 1
    sw      x31, 0x3C(x0)
hang:
    jal     x0,  hang
