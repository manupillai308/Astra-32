.section .text
.globl _start
_start:
    lui     x29, 0x80000
    lui     x30, 0x10000

    addi    x1, x0, 17
    sw      x1, 0(x29)

    lr.w    x2, (x29)
    bne     x2, x1, fail

    addi    x3, x0, 42
    sc.w    x4, x3, (x29)
    bne     x4, x0, fail

    lw      x5, 0(x29)
    bne     x5, x3, fail

    # The successful SC consumed the reservation. A second SC must fail
    # and must not modify memory.
    addi    x6, x0, 99
    sc.w    x7, x6, (x29)
    addi    x8, x0, 1
    bne     x7, x8, fail

    lw      x5, 0(x29)
    bne     x5, x3, fail

pass:
    addi    x1, x0, 1
    sw      x1, 0(x30)
    jal     x0, hang

fail:
    addi    x1, x0, 2
    sw      x1, 0(x30)

hang:
    jal     x0, hang
