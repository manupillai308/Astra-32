.section .text
.globl _start
_start:
    # Physical layout:
    #   0x8000_0000 root page table
    #   0x8000_2000 test word
    lui     x20, 0x80000
    lui     x22, 0x80002
    lui     x30, 0x10000

    # VA 0x4000_0000 -> PA 0x8000_0000 as a 4 MiB RW superpage.
    # Leave A/D clear so the walker must set both before the store.
    lui     x1, 0x20000
    ori     x1, x1, 0x7
    sw      x1, 0x400(x20)       # root[0x100]

    # Identity-map LED MMIO for S-mode completion reporting.
    lui     x1, 0x04000
    ori     x1, x1, 0x0c7
    sw      x1, 0x100(x20)       # root[0x040]

    addi    x2, x0, 0x55
    sw      x2, 0(x22)

    # Enable Sv32 with root PPN 0x80000.
    lui     x1, 0x80080
    csrw    satp, x1

    lui     x1, %hi(supervisor_entry)
    addi    x1, x1, %lo(supervisor_entry)
    csrw    mepc, x1
    addi    x1, x0, 1
    slli    x1, x1, 11           # MPP=S
    csrw    mstatus, x1
    mret

supervisor_entry:
    lui     x10, 0x40002         # VA 0x4000_2000
    lw      x3, 0(x10)
    addi    x4, x0, 0x55
    bne     x3, x4, fail

    addi    x4, x0, 0x6a
    sw      x4, 0(x10)
    lw      x3, 0(x10)
    bne     x3, x4, fail

    # The root PTE is visible through the same superpage mapping.
    lui     x10, 0x40000
    lw      x3, 0x400(x10)
    andi    x3, x3, 0x0c0
    addi    x4, x0, 0x0c0
    bne     x3, x4, fail

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
