# ------------------------------------------------------------
# find_max.s — find the max of a hardcoded 5-element array
#
# Array (init):  [17, 42, 8, 23, 35]  at DMEM[0x00..0x10]
# Result:        max written to DMEM[0x20]   (expected: 42)
# Halt:          DMEM[0x3C] <- 1
#
# We hardcode the array via stores at startup because there's no
# .data section / loader yet — all memory comes up uninitialised.
# ------------------------------------------------------------

.section .text
.globl _start
_start:
    # Initialize array in DMEM
    addi    x1,  x0, 17
    sw      x1,  0(x0)
    addi    x1,  x0, 42
    sw      x1,  4(x0)
    addi    x1,  x0, 8
    sw      x1,  8(x0)
    addi    x1,  x0, 23
    sw      x1,  12(x0)
    addi    x1,  x0, 35
    sw      x1,  16(x0)

    # Scan for max
    addi    x2,  x0, 0          # ptr
    addi    x3,  x0, 20         # end_offset = 5 * 4
    lw      x4,  0(x2)          # max = arr[0]
    addi    x2,  x2, 4

loop:
    bge     x2,  x3, done
    lw      x5,  0(x2)
    bge     x4,  x5, skip       # max >= arr[i] → keep max
    add     x4,  x0, x5         # else max = arr[i]
skip:
    addi    x2,  x2, 4
    jal     x0,  loop

done:
    sw      x4,  0x20(x0)       # store result

    # Halt
    addi    x6,  x0, 1
    sw      x6,  0x3C(x0)
hang:
    jal     x0,  hang
