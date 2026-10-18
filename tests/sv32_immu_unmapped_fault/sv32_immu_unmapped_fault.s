.section .text
.globl _start
_start:
    lui     x20, 0x80000
    lui     x30, 0x10000
    sw      x0, 0x400(x20)     # VA 0x4000_0000 is unmapped.
    jal     x5, run_fault

machine_handler:
    addi    x31, x0, 1
    csrr    x2, mcause
    addi    x3, x0, 12
    bne     x2, x3, fail
    jal     x0, check_address

run_fault:
    lui     x1, %hi(machine_handler)
    addi    x1, x1, %lo(machine_handler)
    csrw    mtvec, x1
    lui     x1, 0x80080
    csrw    satp, x1
    lui     x1, 0x40000
    csrw    mepc, x1
    addi    x1, x0, 1
    slli    x1, x1, 11
    csrw    mstatus, x1
    mret

check_address:
    addi    x31, x0, 2
    lui     x3, 0x40000
    csrr    x2, mepc
    bne     x2, x3, fail
    addi    x31, x0, 3
    csrr    x2, mtval
    bne     x2, x3, fail
    jal     x0, pass

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
