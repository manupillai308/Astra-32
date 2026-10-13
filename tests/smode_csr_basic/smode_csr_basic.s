.section .text
.globl _start
_start:
    lui     x30, 0x10000

    # Independent supervisor trap-state CSRs retain their values.
    addi    x31, x0, 1
    addi    x1, x0, 0x123
    csrw    stvec, x1
    csrr    x2, stvec
    bne     x2, x1, fail

    addi    x1, x0, 0x234
    csrw    sscratch, x1
    csrr    x2, sscratch
    bne     x2, x1, fail

    addi    x1, x0, 0x344
    csrw    sepc, x1
    csrr    x2, sepc
    bne     x2, x1, fail

    addi    x1, x0, 9
    csrw    scause, x1
    csrr    x2, scause
    bne     x2, x1, fail

    addi    x1, x0, 0x456
    csrw    stval, x1
    csrr    x2, stval
    bne     x2, x1, fail

    # sstatus is a masked view of mstatus, not independent storage.
    addi    x31, x0, 2
    lui     x1, 0xC0
    addi    x1, x1, 0x122       # SUM | MXR | SPP | SPIE | SIE
    csrw    sstatus, x1
    csrr    x2, mstatus
    lui     x3, 0xC0
    addi    x3, x3, 0x122
    bne     x2, x3, fail

    lui     x1, 0x40
    addi    x1, x1, 0x12A       # Includes MIE, hidden by sstatus.
    csrw    mstatus, x1
    csrr    x2, sstatus
    lui     x3, 0x40
    addi    x3, x3, 0x122
    bne     x2, x3, fail

    # Only currently supported synchronous exceptions are delegatable.
    addi    x31, x0, 3
    addi    x1, x0, 0x35D
    csrw    medeleg, x1
    csrr    x2, medeleg
    bne     x2, x1, fail

    # Supervisor interrupt bits are SSI=1, STI=5, and SEI=9.
    addi    x31, x0, 4
    addi    x1, x0, -1
    csrw    mideleg, x1
    csrr    x2, mideleg
    addi    x3, x0, 0x222
    bne     x2, x3, fail

    # sie exposes only the delegated supervisor-level subset of mie.
    lui     x1, 0x1
    addi    x1, x1, -1366       # 0x0000_0AAA
    csrw    mie, x1
    csrr    x2, sie
    bne     x2, x3, fail

    addi    x1, x0, 2
    csrw    sie, x1
    csrr    x2, mie
    lui     x3, 0x1
    addi    x3, x3, -1910       # 0x0000_088A
    bne     x2, x3, fail
    csrr    x2, sie
    bne     x2, x1, fail

    # No supervisor interrupt source is connected yet, so sip is zero.
    addi    x31, x0, 5
    csrr    x2, sip
    bne     x2, x0, fail

    # satp storage is present before address translation is enabled.
    addi    x31, x0, 6
    addi    x1, x0, -1
    csrw    satp, x1
    csrr    x2, satp
    bne     x2, x1, fail

pass:
    addi    x1, x0, 1
    sw      x1, 0(x30)
    jal     x0, hang

fail:
    addi    x1, x0, 2
    sw      x1, 0(x30)

hang:
    jal     x0, hang
