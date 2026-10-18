.section .text
.globl _start
_start:
    # root=0x8000_0000, level0=0x8000_1000, code pages at 0x2000/0x3000.
    lui     x20, 0x80000
    lui     x21, 0x80001
    lui     x22, 0x80002
    lui     x23, 0x80003
    lui     x30, 0x10000

    lui     x1, %hi(unexpected_trap)
    addi    x1, x1, %lo(unexpected_trap)
    csrw    mtvec, x1

    # Copy two relocatable functions into separate physical pages.
    lui     x10, %hi(code_one_start)
    addi    x10, x10, %lo(code_one_start)
    lui     x11, %hi(code_one_end)
    addi    x11, x11, %lo(code_one_end)
    add     x12, x22, x0
copy_one:
    lw      x13, 0(x10)
    sw      x13, 0(x12)
    addi    x10, x10, 4
    addi    x12, x12, 4
    bne     x10, x11, copy_one

    lui     x10, %hi(code_two_start)
    addi    x10, x10, %lo(code_two_start)
    lui     x11, %hi(code_two_end)
    addi    x11, x11, %lo(code_two_end)
    add     x12, x23, x0
copy_two:
    lw      x13, 0(x10)
    sw      x13, 0(x12)
    addi    x10, x10, 4
    addi    x12, x12, 4
    bne     x10, x11, copy_two

    fence.i

    # Identity-map ROM as supervisor RX.
    addi    x1, x0, 0x4b
    sw      x1, 0(x20)

    # root[0x100] -> level-0 page table.
    lui     x1, 0x80001
    srli    x1, x1, 2
    ori     x1, x1, 1
    sw      x1, 0x400(x20)

    # VA 0x4000_0000 -> PA 0x8000_2000, supervisor RX, A set.
    lui     x1, 0x80002
    srli    x1, x1, 2
    ori     x1, x1, 0x04b
    sw      x1, 0(x21)

    # VA 0x4040_0000 -> physical page-table region.
    lui     x1, 0x20000
    ori     x1, x1, 0x0c7
    sw      x1, 0x404(x20)

    # Identity-map LED MMIO.
    lui     x1, 0x04000
    ori     x1, x1, 0x0c7
    sw      x1, 0x100(x20)

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
    lui     x14, 0x40000
    jalr    x5, 0(x14)           # Fill ITLB from the first code page.
    addi    x6, x0, 1
    bne     x10, x6, fail_1

    # Replace the executable leaf PTE without fencing.
    lui     x11, 0x40401
    lui     x1, 0x80003
    srli    x1, x1, 2
    ori     x1, x1, 0x04b
    sw      x1, 0(x11)

    # The cached translation must continue executing the first function.
    jalr    x5, 0(x14)
    addi    x6, x0, 1
    bne     x10, x6, fail_2

    sfence.vma x0, x0

    # The refetch after SFENCE.VMA must execute the second function.
    jalr    x5, 0(x14)
    addi    x6, x0, 2
    bne     x10, x6, fail_3

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

.align 2
code_one_start:
    addi    x10, x0, 1
    jalr    x0, 0(x5)
code_one_end:

.align 2
code_two_start:
    addi    x10, x0, 2
    jalr    x0, 0(x5)
code_two_end:
