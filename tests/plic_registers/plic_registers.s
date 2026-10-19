.section .text
.globl _start
_start:
    lui     x30, 0x10000
    lui     x10, 0x0c000          # PLIC base: 0x0c00_0000

    # Source priorities are word-indexed by source ID.
    addi    x1, x0, 5
    sw      x1, 4(x10)            # priority[1]
    lw      x2, 4(x10)
    bne     x1, x2, fail_1

    addi    x1, x0, 3
    sw      x1, 32(x10)           # priority[8]
    lw      x2, 32(x10)
    bne     x1, x2, fail_2

    # Enable source IDs 1 and 8 independently for both contexts.
    lui     x11, 0x0c002          # M enable: 0x0c00_2000
    addi    x1, x0, 0x102
    sw      x1, 0(x11)
    lw      x2, 0(x11)
    bne     x1, x2, fail_3

    addi    x11, x11, 0x80        # S enable: 0x0c00_2080
    sw      x1, 0(x11)
    lw      x2, 0(x11)
    bne     x1, x2, fail_4

    # Each context has an independent priority threshold.
    lui     x12, 0x0c200          # M context: 0x0c20_0000
    addi    x1, x0, 3
    sw      x1, 0(x12)
    lw      x2, 0(x12)
    bne     x1, x2, fail_5

    lui     x13, 0x0c201          # S context: 0x0c20_1000
    addi    x1, x0, 2
    sw      x1, 0(x13)
    lw      x2, 0(x13)
    bne     x1, x2, fail_6

    # No peripheral source is connected yet, so pending and claim are zero.
    lui     x11, 0x0c001          # Pending: 0x0c00_1000
    lw      x2, 0(x11)
    bne     x2, x0, fail_7
    lw      x2, 4(x12)            # M claim
    bne     x2, x0, fail_8
    lw      x2, 4(x13)            # S claim
    bne     x2, x0, fail_9

pass:
    addi    x31, x0, 0
    addi    x1, x0, 1
    sw      x1, 0(x30)
    jal     x0, hang

fail_1:
    addi    x31, x0, 1
    jal     x0, fail
fail_2:
    addi    x31, x0, 2
    jal     x0, fail
fail_3:
    addi    x31, x0, 3
    jal     x0, fail
fail_4:
    addi    x31, x0, 4
    jal     x0, fail
fail_5:
    addi    x31, x0, 5
    jal     x0, fail
fail_6:
    addi    x31, x0, 6
    jal     x0, fail
fail_7:
    addi    x31, x0, 7
    jal     x0, fail
fail_8:
    addi    x31, x0, 8
    jal     x0, fail
fail_9:
    addi    x31, x0, 9

fail:
    addi    x1, x0, 2
    sw      x1, 0(x30)

hang:
    jal     x0, hang
