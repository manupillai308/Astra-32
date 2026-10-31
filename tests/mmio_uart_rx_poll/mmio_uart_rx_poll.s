.section .text
.globl _start
_start:
    lui     x30, 0x10000

wait_for_byte:
    lw      x1, 0x18(x30)
    andi    x1, x1, 2
    beq     x1, x0, wait_for_byte

    lw      x2, 0x14(x30)
    addi    x3, x0, 0x41
    bne     x2, x3, fail

    # Reading RXDATA removes the byte from the FIFO.
    lw      x1, 0x18(x30)
    andi    x1, x1, 2
    bne     x1, x0, fail

    addi    x1, x0, 1
    sw      x1, 0(x30)

hang:
    jal     x0, hang

fail:
    addi    x1, x0, 2
    sw      x1, 0(x30)
    jal     x0, hang
