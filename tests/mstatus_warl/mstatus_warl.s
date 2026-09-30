.section .text
.globl _start
_start:
    lui     x30, 0x10000

    # Unsupported fields and SUM in Bare mode read as zero.
    addi    x31, x0, 1
    addi    x1, x0, -1
    csrw    mstatus, x1
    csrr    x1, mstatus
    lui     x2, 0x7a2
    addi    x2, x2, -1622     # 0x007a19aa
    bne     x1, x2, fail

    # Reserved MPP=2 is coerced to the supported M-mode encoding.
    addi    x31, x0, 2
    lui     x1, 0x1           # MPP=2
    csrw    mstatus, x1
    csrr    x1, mstatus
    lui     x2, 0x2
    addi    x2, x2, -2048     # MPP=M: 0x00001800
    bne     x1, x2, fail

    # Fixed little-endian RV32 without H has no writable mstatush fields.
    addi    x31, x0, 3
    addi    x1, x0, -1
    csrw    mstatush, x1
    csrr    x1, mstatush
    bne     x1, x0, fail

    addi    x31, x0, 0
    addi    x1, x0, 1
    sw      x1, 0(x30)

hang:
    jal     x0, hang

fail:
    addi    x1, x0, 2
    sw      x1, 0(x30)
    jal     x0, hang
