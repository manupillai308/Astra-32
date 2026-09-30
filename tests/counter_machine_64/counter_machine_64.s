.section .text
.globl _start
_start:
    lui     x30, 0x10000

    # RV32 exposes writable high halves for its 64-bit machine counters.
    addi    x31, x0, 1
    addi    x1, x0, 0x12
    csrw    mcycleh, x1
    csrr    x2, mcycleh
    bne     x2, x1, fail
    csrr    x2, cycleh
    bne     x2, x1, fail

    addi    x31, x0, 2
    addi    x1, x0, 0x34
    csrw    minstreth, x1
    csrr    x2, minstreth
    bne     x2, x1, fail
    csrr    x2, instreth
    bne     x2, x1, fail

    # cycle, time, and instret must advance monotonically.
    addi    x31, x0, 3
    csrr    x1, cycle
    csrr    x2, cycle
    bltu    x2, x1, fail

    csrr    x1, time
    csrr    x2, time
    bltu    x2, x1, fail
    csrr    x1, timeh
    bne     x1, x0, fail

    csrr    x1, instret
    csrr    x2, instret
    bltu    x2, x1, fail

    addi    x31, x0, 0
    addi    x1, x0, 1
    sw      x1, 0(x30)

hang:
    jal     x0, hang

fail:
    addi    x1, x0, 2
    sw      x1, 0(x30)
    jal     x0, hang
