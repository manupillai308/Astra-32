.section .text
.globl _start
_start:
    lui     x29, 0x80000
    lui     x30, 0x10000

    lui     x10, %hi(ram_code_start)
    addi    x10, x10, %lo(ram_code_start)
    lui     x11, %hi(ram_code_end)
    addi    x11, x11, %lo(ram_code_end)
    add     x12, x29, x0

copy_loop:
    lw      x13, 0(x10)
    sw      x13, 0(x12)
    addi    x10, x10, 4
    addi    x12, x12, 4
    bne     x10, x11, copy_loop

    jalr    x5, 0(x29)

    addi    x21, x0, 1
    bne     x20, x21, fail

pass:
    addi    x1, x0, 1
    sw      x1, 0(x30)
    jal     x0, hang

fail:
    addi    x1, x0, 2
    sw      x1, 0(x30)

hang:
    jal     x0, hang

.align 2
ram_code_start:
    # Construct the encoding for `addi x20, x0, 1` (0x00100a13).
    lui     x6, 0x00101
    addi    x6, x6, -1517
    # patch_site is five 4-byte instructions from ram_code_start.
    addi    x7, x29, 20
    sw      x6, 0(x7)
    fence.i

patch_site:
    addi    x20, x0, 2
    jalr    x0, 0(x5)
ram_code_end:
