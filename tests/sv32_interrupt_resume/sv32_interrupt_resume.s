.section .text
.globl _start
_start:
    lui     x20, 0x80000
    lui     x22, 0x80002
    lui     x30, 0x10000

    # Supervisor RWAD mapping used while the timer becomes pending.
    lui     x1, 0x20000
    ori     x1, x1, 0x0c7
    sw      x1, 0x400(x20)
    lui     x1, 0x04000
    ori     x1, x1, 0x0c7
    sw      x1, 0x100(x20)
    addi    x2, x0, 0x57
    sw      x2, 0(x22)

    lui     x1, %hi(machine_handler)
    addi    x1, x1, %lo(machine_handler)
    csrw    mtvec, x1
    addi    x28, x0, 0
    addi    x1, x0, 0x80
    csrs    mie, x1

    # Schedule MTIP 256 timer ticks ahead.
    lui     x10, 0x0200c
    lw      x11, -8(x10)
    lw      x12, -4(x10)
    addi    x13, x11, 256
    sltu    x14, x13, x11
    add     x14, x12, x14
    lui     x10, 0x02004
    addi    x15, x0, -1
    sw      x15, 0(x10)
    sw      x14, 4(x10)
    sw      x13, 0(x10)

    lui     x1, 0x80080
    csrw    satp, x1
    lui     x1, %hi(supervisor_entry)
    addi    x1, x1, %lo(supervisor_entry)
    csrw    mepc, x1
    addi    x1, x0, 1
    slli    x1, x1, 11
    ori     x1, x1, 0x80       # MPIE=1, restored into MIE by mret.
    csrw    mstatus, x1
    mret

supervisor_entry:
    lui     x16, 0x40002
translation_loop:
    lw      x3, 0(x16)
    bne     x3, x2, fail
    beq     x28, x0, translation_loop

    # Translation must still work after trap entry and mret.
    lw      x3, 0(x16)
    bne     x3, x2, fail
    jal     x0, pass

machine_handler:
    addi    x31, x0, 1
    csrr    x3, mcause
    lui     x4, 0x80000
    addi    x4, x4, 7
    bne     x3, x4, fail

    lui     x10, 0x02004
    addi    x15, x0, -1
    sw      x15, 0(x10)
    sw      x15, 4(x10)
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
