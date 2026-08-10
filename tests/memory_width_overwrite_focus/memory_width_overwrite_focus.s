# ------------------------------------------------------------
# memory_width_overwrite_focus.s - byte/half overwrite lanes
#
# Expected final word:
#   start: 0xffffffff
#   sb @1: 0xffff12ff
#   sh @2: 0x003412ff
#
# Halt: DMEM[0x3C] <- 1
# ------------------------------------------------------------

.section .text
.globl _start
_start:
    addi    x1,  x0, -1
    sw      x1,  0(x0)

    addi    x2,  x0, 0x12
    sb      x2,  1(x0)

    addi    x3,  x0, 0x34
    sh      x3,  2(x0)

    lw      x4,  0(x0)

    addi    x31, x0, 1
    sw      x31, 0x3C(x0)

hang:
    jal     x0, hang
