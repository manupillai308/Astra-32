.section .text
.globl _start
_start:
    # root=0x8000_0000, level0=0x8000_1000, data pages at 0x2000/0x3000.
    lui     x20, 0x80000
    lui     x21, 0x80001
    lui     x22, 0x80002
    lui     x23, 0x80003
    lui     x30, 0x10000

    lui     x1, %hi(unexpected_trap)
    addi    x1, x1, %lo(unexpected_trap)
    csrw    mtvec, x1

    # Identity-map ROM as supervisor RX.
    addi    x1, x0, 0x4b
    sw      x1, 0(x20)

    # root[0x100] -> level-0 page table.
    lui     x1, 0x80001
    srli    x1, x1, 2
    ori     x1, x1, 1
    sw      x1, 0x400(x20)

    # VA 0x4000_0000 -> PA 0x8000_2000, supervisor RW, A/D set.
    lui     x1, 0x80002
    srli    x1, x1, 2
    ori     x1, x1, 0x0c7
    sw      x1, 0(x21)

    # VA 0x4040_0000 -> physical page-table region.
    lui     x1, 0x20000
    ori     x1, x1, 0x0c7
    sw      x1, 0x404(x20)

    # Identity-map LED MMIO.
    lui     x1, 0x04000
    ori     x1, x1, 0x0c7
    sw      x1, 0x100(x20)

    addi    x1, x0, 0x11
    sw      x1, 0(x22)
    addi    x1, x0, 0x22
    sw      x1, 0(x23)

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
    lw      x2, 0(x10)           # Fill DTLB with the first mapping.
    addi    x3, x0, 0x11
    bne     x2, x3, fail_1

    # Replace the leaf PTE with PA 0x8000_3000 without fencing.
    lui     x11, 0x40401
    lui     x1, 0x80003
    srli    x1, x1, 2
    ori     x1, x1, 0x0c7
    sw      x1, 0(x11)

    # The cached translation must still resolve to the first page.
    lw      x2, 0(x10)
    addi    x3, x0, 0x11
    bne     x2, x3, fail_2

    sfence.vma x0, x0

    # After the fence, the new page-table mapping must be observed.
    lw      x2, 0(x10)
    addi    x3, x0, 0x22
    bne     x2, x3, fail_3

pass:
    addi    x31, x0, 0
    addi    x1, x0, 1
    sw      x1, 0(x30)
    jal     x0, hang

fail_1:
    addi    x31, x0, 1
    jal     x0, fail

fail_2:
    addi    x31, x0, 2
    jal     x0, fail

fail_3:
    addi    x31, x0, 3
    jal     x0, fail

unexpected_trap:
    addi    x31, x0, 4

fail:
    addi    x1, x0, 2
    sw      x1, 0(x30)

hang:
    jal     x0, hang
