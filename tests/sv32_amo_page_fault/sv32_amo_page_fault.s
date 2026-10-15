.section .text
.globl _start
_start:
    lui     x20, 0x80000
    lui     x22, 0x80002
    lui     x30, 0x10000

    # Read-only superpage: AMO writes must receive a store page fault.
    lui     x1, 0x20000
    ori     x1, x1, 0x043       # V | R | A
    sw      x1, 0x400(x20)
    addi    x2, x0, 0x29
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
    addi    x11, x0, 1
    addi    x1, x0, 2
faulting_amo:
    amoadd.w x3, x11, (x10)
    sw      x1, 0(x30)
    jal     x0, hang

machine_handler:
    addi    x31, x0, 1
    csrr    x3, mcause
    addi    x4, x0, 15
    bne     x3, x4, fail

    addi    x31, x0, 2
    csrr    x3, mtval
    lui     x4, 0x40002
    bne     x3, x4, fail

    addi    x31, x0, 3
    csrr    x3, mepc
    lui     x4, %hi(faulting_amo)
    addi    x4, x4, %lo(faulting_amo)
    bne     x3, x4, fail

    # The rejected AMO must not modify physical memory.
    addi    x31, x0, 4
    lw      x3, 0(x22)
    bne     x3, x2, fail

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
