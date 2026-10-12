.section .text
.globl _start
_start:
    lui     x29, 0x80000
    lui     x30, 0x10000

    addi    x1, x0, 11
    sw      x1, 0(x29)

    # A store to another word does not overlap this implementation's
    # four-byte reservation granule.
    lr.w    x2, (x29)
    addi    x3, x0, 22
    sw      x3, 4(x29)
    addi    x4, x0, 33
    sc.w    x5, x4, (x29)
    bne     x5, x0, fail
    lw      x6, 0(x29)
    bne     x6, x4, fail

    # An overlapping local store invalidates the reservation, so SC fails.
    lr.w    x2, (x29)
    addi    x3, x0, 44
    sw      x3, 0(x29)
    addi    x4, x0, 55
    sc.w    x5, x4, (x29)
    addi    x6, x0, 1
    bne     x5, x6, fail
    lw      x6, 0(x29)
    bne     x6, x3, fail

pass:
    addi    x1, x0, 1
    sw      x1, 0(x30)
    jal     x0, hang

fail:
    addi    x1, x0, 2
    sw      x1, 0(x30)

hang:
    jal     x0, hang
