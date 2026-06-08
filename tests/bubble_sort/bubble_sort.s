# ------------------------------------------------------------
# bubble_sort.s — sort a hardcoded 5-element array ascending
#
# Array (init):    [5, 2, 8, 1, 4]  at DMEM[0x00..0x10]
# Array (after):   [1, 2, 4, 5, 8]
# Halt:            DMEM[0x3C] <- 1
#
# Standard bubble sort: outer pass shrinks the unsorted region by 1
# each time (largest element bubbles to the end). Early-exit if a
# pass produces no swaps.
# ------------------------------------------------------------

.section .text
.globl _start
_start:
    # Initialize array
    addi    x1,  x0, 5
    sw      x1,  0(x0)
    addi    x1,  x0, 2
    sw      x1,  4(x0)
    addi    x1,  x0, 8
    sw      x1,  8(x0)
    addi    x1,  x0, 1
    sw      x1,  12(x0)
    addi    x1,  x0, 4
    sw      x1,  16(x0)

    addi    x10, x0, 5          # n = remaining unsorted length

outer:
    addi    x12, x0, 0          # swapped = 0
    addi    x13, x0, 0          # i = 0
    addi    x14, x10, -1        # n - 1

inner:
    bge     x13, x14, after_inner
    slli    x15, x13, 2         # offset = i * 4
    lw      x17, 0(x15)         # a = arr[i]
    lw      x18, 4(x15)         # b = arr[i+1]
    bge     x18, x17, no_swap   # b >= a → already in order
    sw      x18, 0(x15)         # swap
    sw      x17, 4(x15)
    addi    x12, x0, 1          # swapped = 1
no_swap:
    addi    x13, x13, 1
    jal     x0,  inner

after_inner:
    beq     x12, x0, done       # no swaps → sorted
    addi    x10, x10, -1        # shrink unsorted region
    jal     x0,  outer

done:
    # Halt
    addi    x6,  x0, 1
    sw      x6,  0x3C(x0)
hang:
    jal     x0,  hang
