# ------------------------------------------------------------
# load_to_jalr_focus.s - load result used as JALR base
#
# Expected:
#   DMEM[4] = 1
#   x3 = return PC from jalr
#
# Halt: DMEM[0x3C] <- 1
# ------------------------------------------------------------

.section .text
.globl _start
_start:
    addi    x1,  x0, 0x1C        # target address
    sw      x1,  0(x0)
    lw      x2,  0(x0)
    jalr    x3,  0(x2)

wrong_path:
    addi    x4,  x0, 2
    sw      x4,  4(x0)
    jal     x0,  done

target:
    addi    x4,  x0, 1
    sw      x4,  4(x0)

done:
    addi    x31, x0, 1
    sw      x31, 0x3C(x0)

hang:
    jal     x0, hang
