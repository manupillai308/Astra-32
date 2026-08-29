.section .text
.globl _start
_start:
    lui     x1, 0x10000

    addi    x2, x0, 72
    jal     x5, putc
    addi    x2, x0, 101
    jal     x5, putc

wait_last_tx:
    lw      x3, 0x18(x1)
    andi    x3, x3, 1
    beq     x3, x0, wait_last_tx

    addi    x4, x0, 1
    sw      x4, 0(x1)

hang:
    jal     x0, hang

putc:
wait_tx_ready:
    lw      x3, 0x18(x1)
    andi    x3, x3, 1
    beq     x3, x0, wait_tx_ready

    sw      x2, 0x10(x1)
    jalr    x0, 0(x5)
