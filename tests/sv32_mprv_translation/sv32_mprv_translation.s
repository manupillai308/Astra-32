.section .text
.globl _start
_start:
    lui     x20, 0x80000
    lui     x22, 0x80002
    lui     x30, 0x10000

    # VA 0x4000_0000 -> PA 0x8000_0000, RWAD superpage.
    lui     x1, 0x20000
    ori     x1, x1, 0x0c7
    sw      x1, 0x400(x20)
    addi    x2, x0, 0x5c
    sw      x2, 0(x22)

    lui     x1, 0x80080
    csrw    satp, x1

    # Remain in M-mode, but use S-mode translation and permissions for data.
    lui     x1, 0x21
    addi    x1, x1, -2048      # MPRV=1, MPP=S
    csrw    mstatus, x1

    lui     x10, 0x40002
    lw      x3, 0(x10)

    # Disable MPRV before accessing physical LED MMIO.
    csrw    mstatus, x0
    bne     x3, x2, fail

pass:
    addi    x31, x0, 0
    addi    x1, x0, 1
    sw      x1, 0(x30)
    jal     x0, hang

fail:
    addi    x31, x0, 1
    addi    x1, x0, 2
    sw      x1, 0(x30)

hang:
    jal     x0, hang
