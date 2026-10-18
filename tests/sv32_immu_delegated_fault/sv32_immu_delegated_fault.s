.section .text
.globl _start
_start:
    lui     x20, 0x80000
    lui     x30, 0x10000

    # Keep the U-mode target unmapped. Map VA 0x0040_0000 as a
    # supervisor-only alias of ROM for the delegated trap handler.
    sw      x0, 0x400(x20)
    addi    x1, x0, 0x4b       # V | R | X | A
    sw      x1, 4(x20)

    # Identity-map LED MMIO for S-mode completion reporting.
    lui     x1, 0x04000
    ori     x1, x1, 0x0c7
    sw      x1, 0x100(x20)

    lui     x1, %hi(supervisor_handler)
    addi    x1, x1, %lo(supervisor_handler)
    lui     x5, 0x400
    add     x1, x1, x5
    csrw    stvec, x1
    lui     x1, 0x1            # Delegate cause 12.
    csrw    medeleg, x1

    lui     x1, 0x80080
    csrw    satp, x1
    lui     x1, 0x40000
    csrw    mepc, x1
    csrw    mstatus, x0        # MPP=U
    mret

supervisor_handler:
    addi    x31, x0, 1
    csrr    x2, scause
    addi    x3, x0, 12
    bne     x2, x3, fail

    addi    x31, x0, 2
    lui     x3, 0x40000
    csrr    x2, sepc
    bne     x2, x3, fail

    addi    x31, x0, 3
    csrr    x2, stval
    bne     x2, x3, fail

pass:
    addi    x31, x0, 0
    addi    x1, x0, 1
    sw      x1, 0(x30)
    jal     x0, hang
fail:
    addi    x1, x0, 2
    sw      x1, 0(x30)
hang:
    jal     x0, hang
