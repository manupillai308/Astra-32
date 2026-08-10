# ------------------------------------------------------------
# signed_load_ext_focus.s - signed and unsigned byte/half loads
#
# Expected:
#   x2 = ffffff80   lb  0
#   x3 = 00000080   lbu 0
#   x4 = ffffffff   lb  1
#   x5 = 000000ff   lbu 1
#   x6 = ffff8000   lh  2
#   x7 = 00008000   lhu 2
#
# Halt: DMEM[0x3C] <- 1
# ------------------------------------------------------------

.section .text
.globl _start
_start:
    addi    x1,  x0, 0x80
    sb      x1,  0(x0)
    addi    x1,  x0, -1
    sb      x1,  1(x0)
    sb      x0,  2(x0)
    addi    x1,  x0, 0x80
    sb      x1,  3(x0)

    lb      x2,  0(x0)
    lbu     x3,  0(x0)
    lb      x4,  1(x0)
    lbu     x5,  1(x0)
    lh      x6,  2(x0)
    lhu     x7,  2(x0)

    addi    x31, x0, 1
    sw      x31, 0x3C(x0)

hang:
    jal     x0, hang
