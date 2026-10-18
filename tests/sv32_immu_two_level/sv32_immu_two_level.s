.section .text
.globl _start
_start:
    lui     x20, 0x80000       # Root page table
    lui     x21, 0x80001       # Level-0 page table
    lui     x30, 0x10000

    # root[0x100] points to the level-0 table at 0x8000_1000.
    lui     x1, 0x80001
    srli    x1, x1, 2
    ori     x1, x1, 1          # V, non-leaf
    sw      x1, 0x400(x20)

    # VA 0x4000_0000 maps physical ROM page zero. Leave A clear.
    addi    x1, x0, 0x0b       # V | R | X
    sw      x1, 0(x21)

    lui     x1, %hi(machine_handler)
    addi    x1, x1, %lo(machine_handler)
    csrw    mtvec, x1
    lui     x1, 0x80080
    csrw    satp, x1

    lui     x1, %hi(translated_entry)
    addi    x1, x1, %lo(translated_entry)
    lui     x2, 0x40000
    add     x1, x1, x2
    csrw    mepc, x1
    addi    x1, x0, 1
    slli    x1, x1, 11         # MPP=S
    csrw    mstatus, x1
    mret

translated_entry:
    addi    x27, x0, 0x6a
    ecall

machine_handler:
    addi    x31, x0, 1
    csrr    x2, mcause
    addi    x3, x0, 9
    bne     x2, x3, fail

    addi    x31, x0, 2
    addi    x3, x0, 0x6a
    bne     x27, x3, fail

    addi    x31, x0, 3
    lw      x2, 0(x21)
    andi    x2, x2, 0xc0       # A must be set; D must remain clear.
    addi    x3, x0, 0x40
    bne     x2, x3, fail

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
