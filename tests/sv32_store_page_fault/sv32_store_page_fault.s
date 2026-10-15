.section .text
.globl _start
_start:
    lui     x20, 0x80000
    lui     x22, 0x80002
    lui     x30, 0x10000

    # Read-only superpage mapping with A already set.
    lui     x1, 0x20000
    ori     x1, x1, 0x043       # V | R | A
    sw      x1, 0x400(x20)

    addi    x2, x0, 0x2a
    sw      x2, 0(x22)

    lui     x1, %hi(machine_handler)
    addi    x1, x1, %lo(machine_handler)
    csrw    mtvec, x1

    lui     x1, 0x80080
    csrw    satp, x1
    lui     x1, %hi(supervisor_entry)
    addi    x1, x1, %lo(supervisor_entry)
    csrw    mepc, x1
    addi    x1, x0, 1
    slli    x1, x1, 11
    csrw    mstatus, x1
    mret

supervisor_entry:
    lui     x10, 0x40002
    addi    x4, x0, 0x63
    addi    x1, x0, 2
faulting_store:
    sw      x4, 0(x10)
    sw      x1, 0(x30)
    jal     x0, hang

machine_handler:
    addi    x31, x0, 1
    csrr    x5, mcause
    addi    x6, x0, 15
    bne     x5, x6, fail

    addi    x31, x0, 2
    csrr    x5, mtval
    lui     x6, 0x40002
    bne     x5, x6, fail

    addi    x31, x0, 3
    csrr    x5, mepc
    lui     x6, %hi(faulting_store)
    addi    x6, x6, %lo(faulting_store)
    bne     x5, x6, fail

    # Trap entry is M-mode, so this physical check bypasses translation.
    addi    x31, x0, 4
    lw      x5, 0(x22)
    bne     x5, x2, fail

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
