.section .text
.globl _start
_start:
    lui     x20, 0x80000       # Root page table
    lui     x21, 0x80001       # Instruction level-0 table
    lui     x22, 0x80002       # Data level-0 table
    lui     x23, 0x80003       # Physical RAM code page
    lui     x30, 0x10000

    # Copy the translated code block into physical RAM at 0x8000_3000.
    lui     x10, %hi(ram_code_start)
    addi    x10, x10, %lo(ram_code_start)
    lui     x11, %hi(ram_code_end)
    addi    x11, x11, %lo(ram_code_end)
    add     x12, x23, x0
copy_loop:
    lw      x13, 0(x10)
    sw      x13, 0(x12)
    addi    x10, x10, 4
    addi    x12, x12, 4
    bne     x10, x11, copy_loop

    # VA 0x4000_0000 uses the instruction level-0 table.
    lui     x1, 0x80001
    srli    x1, x1, 2
    ori     x1, x1, 1
    sw      x1, 0x400(x20)

    # VA 0x4040_0000 uses a separate data level-0 table.
    lui     x1, 0x80002
    srli    x1, x1, 2
    ori     x1, x1, 1
    sw      x1, 0x404(x20)

    # Both virtual pages target physical RAM page 0x8000_3000, with RX
    # permission on the instruction alias and RW on the data alias. Leave A
    # clear so the first competing walks also serialize PTE updates.
    lui     x1, 0x80003
    srli    x1, x1, 2
    ori     x1, x1, 0x0b       # V | R | X
    sw      x1, 0(x21)
    lui     x1, 0x80003
    srli    x1, x1, 2
    ori     x1, x1, 0x7        # V | R | W
    sw      x1, 0(x22)

    # Identity-map LED MMIO for S-mode completion reporting.
    lui     x1, 0x04000
    ori     x1, x1, 0x0c7
    sw      x1, 0x100(x20)

    addi    x24, x23, 0x100
    addi    x1, x0, 0x55
    sw      x1, 0(x24)

    lui     x1, 0x80080
    csrw    satp, x1
    lui     x1, 0x40000
    csrw    mepc, x1
    addi    x1, x0, 1
    slli    x1, x1, 11         # MPP=S
    csrw    mstatus, x1
    mret

    # Everything below is copied as one position-independent RAM code block.
    .align 2
ram_code_start:
    lui     x10, 0x40400
    addi    x10, x10, 0x100
    addi    x6, x0, 16
    addi    x27, x0, 0

contention_loop:
    lw      x3, 0(x10)
    addi    x4, x0, 0x55
    bne     x3, x4, fail
    addi    x27, x27, 1
    addi    x6, x6, -1
    bne     x6, x0, contention_loop

    addi    x4, x0, 16
    bne     x27, x4, fail

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
ram_code_end:
