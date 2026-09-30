.section .text
.globl _start
_start:
    lui     x30, 0x10000

    addi    x31, x0, 1
    csrr    x1, misa
    lui     x2, 0x40140
    addi    x2, x2, 256
    bne     x1, x2, fail

    # misa is implemented as a constant WARL value for the current ISA.
    addi    x1, x0, -1
    csrw    misa, x1
    csrr    x1, misa
    bne     x1, x2, fail

    addi    x31, x0, 2
    csrr    x1, mvendorid
    bne     x1, x0, fail

    addi    x31, x0, 3
    csrr    x1, marchid
    bne     x1, x0, fail

    addi    x31, x0, 4
    csrr    x1, mimpid
    bne     x1, x0, fail

    addi    x31, x0, 5
    csrr    x1, mhartid
    bne     x1, x0, fail

    addi    x31, x0, 6
    csrr    x1, 0xf15       # mconfigptr
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
