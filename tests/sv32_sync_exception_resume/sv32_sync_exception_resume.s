.section .text
.globl _start
_start:
    lui     x20, 0x80000
    lui     x22, 0x80002
    lui     x30, 0x10000

    # Supervisor RWAD mapping for translated data accesses.
    lui     x1, 0x20000
    ori     x1, x1, 0x0c7
    sw      x1, 0x400(x20)
    lui     x1, 0x04000
    ori     x1, x1, 0x0c7
    sw      x1, 0x100(x20)
    addi    x2, x0, 0x31
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
    slli    x1, x1, 11         # MPP=S
    csrw    mstatus, x1
    mret

supervisor_entry:
    lui     x10, 0x40002
    lw      x3, 0(x10)
    bne     x3, x2, fail

faulting_ecall:
    ecall

after_ecall:
    addi    x4, x0, 0x62
    sw      x4, 4(x10)
    lw      x5, 4(x10)
    bne     x5, x4, fail
    addi    x6, x0, 1
    bne     x28, x6, fail
    jal     x0, pass

machine_handler:
    addi    x31, x0, 1
    csrr    x5, mcause
    addi    x6, x0, 9
    bne     x5, x6, fail

    addi    x31, x0, 2
    csrr    x5, mepc
    lui     x6, %hi(faulting_ecall)
    addi    x6, x6, %lo(faulting_ecall)
    bne     x5, x6, fail

    addi    x5, x5, 4
    csrw    mepc, x5
    addi    x28, x0, 1
    mret

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
