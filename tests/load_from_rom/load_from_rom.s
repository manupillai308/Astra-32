.section .text
.globl _start
_start:
    lui     x30, 0x10000

    addi    x10, x0, 0x100

    lw      x1,  0(x10)
    lbu     x2,  0(x10)
    lb      x3,  3(x10)
    lhu     x4,  4(x10)
    lh      x5,  6(x10)

    lui     x11, 0x11223
    addi    x11, x11, 0x344
    bne     x1,  x11, fail

    addi    x11, x0, 0x44
    bne     x2,  x11, fail

    addi    x11, x0, 0x11
    bne     x3,  x11, fail

    lui     x11, 0x0000a
    addi    x11, x11, 0x655
    bne     x4,  x11, fail

    addi    x11, x0, -0x100
    bne     x5,  x11, fail

    jal     x0,  pass

pass:
    addi    x1,  x0, 1
    sw      x1,  0(x30)
    jal     x0,  hang

fail:
    addi    x1,  x0, 2
    sw      x1,  0(x30)

hang:
    jal     x0,  hang

.org 0x100
rom_data:
    .word   0x11223344
    .word   0xff00a655
