.section .text
.globl _start
_start:
    lui  x5, 0x12345
    addi x6, x5, 1
    addi x7, x6, 1

hang:
    jal     x0,  hang
