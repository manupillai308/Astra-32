# ------------------------------------------------------------
# fibonacci.s — write the first 10 Fibonacci numbers to DMEM
#
# DMEM layout after run:
#   0x00 .. 0x24   fib[0..9]   (10 words: 0,1,1,2,3,5,8,13,21,34)
#   0x3C           halt sentinel (= 1)
# ------------------------------------------------------------

.section .text
.globl _start
_start:
    addi    x1,  x0, 0          # a = 0
    addi    x2,  x0, 1          # b = 1
    addi    x3,  x0, 10         # count = 10
    addi    x4,  x0, 0          # ptr = 0

    sw      x1,  0(x4)          # fib[0]
    addi    x4,  x4, 4
    sw      x2,  0(x4)          # fib[1]
    addi    x4,  x4, 4
    addi    x3,  x3, -2         # count -= 2 (already stored 2)

loop:
    beq     x3,  x0, done
    add     x5,  x1, x2         # next = a + b
    sw      x5,  0(x4)
    addi    x4,  x4, 4
    add     x1,  x0, x2         # a = b
    add     x2,  x0, x5         # b = next
    addi    x3,  x3, -1
    jal     x0,  loop

done:
    # Halt: write non-zero to 0x3C so testbench finishes.
    addi    x6,  x0, 1
    sw      x6,  0x3C(x0)
hang:
    jal     x0,  hang
