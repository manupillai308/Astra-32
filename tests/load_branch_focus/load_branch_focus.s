.section .text
.globl _start
_start:
    lui     x29, 0x80000
    lui     x30, 0x10000

    addi    x1,  x0, 5
    sw      x1,  0(x29)
    addi    x1,  x0, 2
    sw      x1,  4(x29)

    lw      x17, 0(x29)
    lw      x18, 4(x29)
    bge     x18, x17, fail
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
