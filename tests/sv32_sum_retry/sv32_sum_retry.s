.section .text
.globl _start
_start:
    lui     x20, 0x80000
    lui     x22, 0x80002
    lui     x30, 0x10000

    # User-accessible RWAD superpage.
    lui     x1, 0x20000
    ori     x1, x1, 0x0d7       # V | R | W | U | A | D
    sw      x1, 0x400(x20)

    # Supervisor-only identity mapping for LED MMIO.
    lui     x1, 0x04000
    ori     x1, x1, 0x0c7
    sw      x1, 0x100(x20)

    addi    x2, x0, 0x4d
    sw      x2, 0(x22)

    lui     x1, %hi(supervisor_handler)
    addi    x1, x1, %lo(supervisor_handler)
    csrw    stvec, x1
    lui     x1, 0x2             # Delegate load page fault, cause 13.
    csrw    medeleg, x1

    lui     x1, 0x80080
    csrw    satp, x1
    lui     x1, %hi(supervisor_entry)
    addi    x1, x1, %lo(supervisor_entry)
    csrw    mepc, x1
    addi    x1, x0, 1
    slli    x1, x1, 11          # MPP=S, SUM remains clear.
    csrw    mstatus, x1
    mret

supervisor_entry:
    lui     x10, 0x40002
    addi    x7, x0, 2
faulting_load:
    lw      x3, 0(x10)
    sw      x7, 0(x30)
    bne     x3, x2, fail
    addi    x4, x0, 1
    bne     x28, x4, fail
    jal     x0, pass

supervisor_handler:
    addi    x31, x0, 1
    csrr    x5, scause
    addi    x6, x0, 13
    bne     x5, x6, fail
    csrr    x5, stval
    lui     x6, 0x40002
    bne     x5, x6, fail
    csrr    x5, sepc
    lui     x6, %hi(faulting_load)
    addi    x6, x6, %lo(faulting_load)
    bne     x5, x6, fail

    # Permit S-mode data access to U pages, then retry the same load.
    lui     x5, 0x40            # sstatus.SUM, bit 18
    csrs    sstatus, x5
    addi    x7, x0, 0           # Make the post-retry store harmless.
    addi    x28, x0, 1
    sret

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
