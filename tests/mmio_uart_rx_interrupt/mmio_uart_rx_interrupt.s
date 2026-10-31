.section .text
.globl _start
_start:
    lui     x30, 0x10000

    lui     x1, %hi(trap_handler)
    addi    x1, x1, %lo(trap_handler)
    csrw    mtvec, x1

    # PLIC source 1 is UART RX. Give it priority 1, enable it for the
    # machine context, and leave the machine threshold at zero.
    lui     x10, 0x0c000
    addi    x1, x0, 1
    sw      x1, 4(x10)
    addi    x1, x0, 2
    lui     x11, 0x0c002
    sw      x1, 0(x11)
    lui     x12, 0x0c200
    sw      x0, 0(x12)

    # Enable UART RX interrupts, then enable machine external interrupts.
    addi    x1, x0, 1
    sw      x1, 0x1c(x30)
    lui     x1, 1
    srli    x1, x1, 1
    csrs    mie, x1
    addi    x1, x0, 8
    csrs    mstatus, x1

    # All interrupt routing is configured; request the UART frame now.
    addi    x1, x0, 4
    sw      x1, 0(x30)

wait_for_interrupt:
    lw      x8, 0x18(x30)
    andi    x9, x8, 0x1c
    bne     x9, x0, uart_status_fail
    jal     x0, wait_for_interrupt

trap_handler:
    csrr    x2, mcause
    lui     x3, 0x80000
    addi    x3, x3, 11
    bne     x2, x3, fail

    # Claiming must return UART source ID 1.
    lw      x4, 4(x12)
    addi    x5, x0, 1
    bne     x4, x5, fail

    # Verify the interrupt corresponds to available, error-free RX data.
    lw      x8, 0x18(x30)
    andi    x9, x8, 0x1c
    bne     x9, x0, uart_status_fail
    andi    x9, x8, 2
    beq     x9, x0, fail

    # Draining RXDATA deasserts the UART's level interrupt.
    lw      x6, 0x14(x30)
    addi    x7, x0, 0x5a
    bne     x6, x7, fail

    # Complete source 1 after its device-level condition is cleared.
    sw      x4, 4(x12)

    addi    x1, x0, 1
    sw      x1, 0(x30)

hang:
    jal     x0, hang

fail:
    addi    x1, x0, 2
    sw      x1, 0(x30)
    jal     x0, hang

uart_status_fail:
    addi    x31, x0, 1
    jal     x0, fail
