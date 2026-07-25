.section .text
.globl _start
_start:
    lui  x1, 0x10000
    addi x2, x0, 5
    sw   x2, 0(x1)

    addi x3, x0, 1
    sw   x3, 0x3C(x0)

    hang:
        jal x0, hang
