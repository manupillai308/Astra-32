
.section .text
.globl _start
_start:
    addi   x1, x0, 2          # x1 = 2
    addi   x2, x0, 3          # x2 = 3
    add    x3, x1, x2         # x3 = 5

    addi   x4, x0, 1          # halt value
    sw     x4, 0x3C(x0)       # write to halt address (last word of DMEM)

hang:
    jal    x0, hang           # park here forever (safety, in case TB misses halt)