.section .text
.globl _start
_start:
    lui     x20, 0x80000
    lui     x30, 0x10000

    # User executable mapping. S-mode instruction fetch must reject it,
    # including when mstatus.SUM is set.
    addi    x1, x0, 0x5b       # V | R | X | U | A
    sw      x1, 0x400(x20)

    lui     x1, %hi(machine_handler)
    addi    x1, x1, %lo(machine_handler)
    csrw    mtvec, x1
    lui     x1, 0x80080
    csrw    satp, x1
    lui     x1, 0x40000
    csrw    mepc, x1
    lui     x1, 0x40           # SUM=1
    addi    x2, x0, 1
    slli    x2, x2, 11         # MPP=S
    or      x1, x1, x2
    csrw    mstatus, x1
    mret

machine_handler:
    addi    x31, x0, 1
    csrr    x2, mcause
    addi    x3, x0, 12
    bne     x2, x3, fail
    addi    x31, x0, 2
    lui     x3, 0x40000
    csrr    x2, mepc
    bne     x2, x3, fail
    addi    x31, x0, 3
    csrr    x2, mtval
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
