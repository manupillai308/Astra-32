.section .text
.globl _start
_start:
    lui  x1, 0x10000      # MMIO base: 0x1000_0000

    addi x2, x0, 65       # ASCII 'A'
    sw   x2, 0x10(x1)     # UART_TXDATA

wait_tx_ready:
    lw   x3, 0x18(x1)     # UART_STATUS
    andi x3, x3, 1        # bit 0: tx_ready
    beq  x3, x0, wait_tx_ready

    addi x4, x0, 1
    sw   x4, 0x3C(x0)     # halt

hang:
    jal  x0, hang
