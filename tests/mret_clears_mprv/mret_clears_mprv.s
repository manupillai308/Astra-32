.section .text
.globl _start
_start:
    lui     x30, 0x10000

    lui     x1, %hi(machine_handler)
    addi    x1, x1, %lo(machine_handler)
    csrw    mtvec, x1

    lui     x1, %hi(supervisor_entry)
    addi    x1, x1, %lo(supervisor_entry)
    csrw    mepc, x1

    # MRET to S-mode must clear MPRV.
    lui     x1, 0x21
    addi    x1, x1, -2048     # MPRV | MPP=S
    csrw    mstatus, x1
    addi    x31, x0, 1
    mret

supervisor_entry:
    ecall
    jal     x0, fail

machine_handler:
    addi    x31, x0, 2
    csrr    x1, mstatus
    lui     x2, 0x20           # MPRV
    and     x1, x1, x2
    bne     x1, x0, fail

    addi    x31, x0, 0
    addi    x1, x0, 1
    sw      x1, 0(x30)
    jal     x0, hang

fail:
    addi    x1, x0, 2
    sw      x1, 0(x30)

hang:
    jal     x0, hang
