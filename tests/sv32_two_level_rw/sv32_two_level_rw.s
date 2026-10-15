.section .text
.globl _start
_start:
    # root=0x8000_0000, level0=0x8000_1000, data=0x8000_2000.
    lui     x20, 0x80000
    lui     x21, 0x80001
    lui     x22, 0x80002
    lui     x30, 0x10000

    # root[0x100] -> level-0 table at 0x8000_1000.
    lui     x1, 0x80001
    srli    x1, x1, 2
    ori     x1, x1, 1
    sw      x1, 0x400(x20)

    # level0[1]: VA 0x4000_1000 -> PA 0x8000_2000, RW with A/D clear.
    lui     x1, 0x80002
    srli    x1, x1, 2
    ori     x1, x1, 7
    sw      x1, 4(x21)

    # VA 0x4040_0000 maps the physical page-table region for PTE checks.
    lui     x1, 0x20000
    ori     x1, x1, 0x0c7
    sw      x1, 0x404(x20)       # root[0x101]

    # Identity-map LED MMIO.
    lui     x1, 0x04000
    ori     x1, x1, 0x0c7
    sw      x1, 0x100(x20)

    addi    x2, x0, 0x39
    sw      x2, 0(x22)

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
    lui     x10, 0x40001
    lw      x3, 0(x10)
    addi    x4, x0, 0x39
    bne     x3, x4, fail

    addi    x4, x0, 0x73
    sw      x4, 0(x10)
    lw      x3, 0(x10)
    bne     x3, x4, fail

    # Read level0[1] through VA 0x4040_1004 and verify A/D were set.
    lui     x10, 0x40401
    lw      x3, 4(x10)
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
