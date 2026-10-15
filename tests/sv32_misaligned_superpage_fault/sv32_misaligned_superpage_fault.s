.section .text
.globl _start
_start:
    lui     x20, 0x80000
    lui     x30, 0x10000

    # A level-1 leaf must have PPN[0]=0. Pointing at 0x8000_1000
    # deliberately violates the 4 MiB superpage alignment requirement.
    lui     x1, 0x80001
    srli    x1, x1, 2
    ori     x1, x1, 0x043
    sw      x1, 0x400(x20)

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
    lui     x10, 0x40000
    addi    x27, x0, 0x35
faulting_load:
    lw      x2, 0(x10)
    addi    x27, x0, 0x6a
    jal     x0, hang

machine_handler:
    addi    x31, x0, 1
    addi    x3, x0, 0x35
    bne     x27, x3, fail
    csrr    x2, mcause
    addi    x3, x0, 13
    bne     x2, x3, fail
    csrr    x2, mtval
    lui     x3, 0x40000
    bne     x2, x3, fail
    csrr    x2, mepc
    lui     x3, %hi(faulting_load)
    addi    x3, x3, %lo(faulting_load)
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
