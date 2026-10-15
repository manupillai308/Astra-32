.section .text
.globl _start
_start:
    lui     x20, 0x80000
    lui     x30, 0x10000

    # Leave the target VA unmapped. Map LED MMIO for the S-mode handler.
    sw      x0, 0x400(x20)
    lui     x1, 0x04000
    ori     x1, x1, 0x0c7
    sw      x1, 0x100(x20)

    lui     x1, %hi(machine_handler)
    addi    x1, x1, %lo(machine_handler)
    csrw    mtvec, x1
    lui     x1, %hi(supervisor_handler)
    addi    x1, x1, %lo(supervisor_handler)
    csrw    stvec, x1

    # Delegate load page faults to S-mode.
    lui     x1, 0x2
    csrw    medeleg, x1
    lui     x1, 0x80080
    csrw    satp, x1

    lui     x1, %hi(user_entry)
    addi    x1, x1, %lo(user_entry)
    csrw    mepc, x1
    csrw    mstatus, x0        # MPP=U
    mret

user_entry:
    lui     x10, 0x40002
    addi    x27, x0, 0x35
faulting_load:
    lw      x2, 0(x10)
    addi    x27, x0, 0x6a
    jal     x0, hang

supervisor_handler:
    addi    x31, x0, 1
    addi    x3, x0, 0x35
    bne     x27, x3, fail
    csrr    x2, scause
    addi    x3, x0, 13
    bne     x2, x3, fail

    addi    x31, x0, 2
    csrr    x2, stval
    lui     x3, 0x40002
    bne     x2, x3, fail

    addi    x31, x0, 3
    csrr    x2, sepc
    lui     x3, %hi(faulting_load)
    addi    x3, x3, %lo(faulting_load)
    bne     x2, x3, fail

pass:
    addi    x31, x0, 0
    addi    x1, x0, 1
    sw      x1, 0(x30)
    jal     x0, hang

machine_handler:
    addi    x31, x0, 4

fail:
    addi    x1, x0, 2
    sw      x1, 0(x30)

hang:
    jal     x0, hang
