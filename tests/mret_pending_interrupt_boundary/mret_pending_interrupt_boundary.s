.section .text
.globl _start
_start:
    # RAM contains a sentinel. The first instruction at the mret target
    # attempts to overwrite it and must not execute before pending MSIP.
    lui     x29, 0x80000       # RAM base:   0x8000_0000
    lui     x30, 0x10000       # LED MMIO:   0x1000_0000
    lui     x10, 0x02000       # CLINT MSIP: 0x0200_0000

    lui     x1, %hi(trap_handler)
    addi    x1, x1, %lo(trap_handler)
    csrw    mtvec, x1

    addi    x2, x0, 1
    sw      x2, 0(x29)         # Original sentinel.
    addi    x3, x0, 2          # Forbidden younger-store value.

    # Enable machine software interrupts while MSIP remains clear.
    addi    x1, x0, 0x8
    csrs    mie, x1
    csrs    mstatus, x1

    # Enter a synchronous trap with MPIE=1 and MIE cleared by trap entry.
    ecall

after_mret:
    # A pending interrupt must be taken immediately after mret, before this
    # return-target instruction can produce a visible side effect.
    sw      x3, 0(x29)
    addi    x31, x0, 1
    jal     x0, fail

trap_handler:
    csrr    x4, mcause
    blt     x4, x0, software_interrupt_handler

ecall_handler:
    addi    x5, x0, 11
    bne     x4, x5, fail_ecall_cause

    # Skip the ecall on return, then raise MSIP while trap entry keeps
    # mstatus.MIE clear. mret must restore MIE and immediately recheck it.
    csrr    x5, mepc
    addi    x5, x5, 4
    csrw    mepc, x5
    sw      x2, 0(x10)
    mret

software_interrupt_handler:
    lui     x5, 0x80000
    addi    x5, x5, 3
    bne     x4, x5, fail_interrupt_cause

    # The interrupted instruction must be the first instruction at the
    # return target, not an instruction after its store side effect.
    csrr    x4, mepc
    lui     x5, %hi(after_mret)
    addi    x5, x5, %lo(after_mret)
    bne     x4, x5, fail_mepc

    sw      x0, 0(x10)         # Clear level-sensitive MSIP.
    lw      x4, 0(x29)
    bne     x4, x2, fail_memory

    addi    x1, x0, 1
    sw      x1, 0(x30)
    jal     x0, hang

fail_ecall_cause:
    addi    x31, x0, 2
    jal     x0, fail

fail_interrupt_cause:
    addi    x31, x0, 3
    jal     x0, fail

fail_mepc:
    addi    x31, x0, 4
    jal     x0, fail

fail_memory:
    addi    x31, x0, 5

fail:
    sw      x0, 0(x10)
    addi    x1, x0, 2
    sw      x1, 0(x30)

hang:
    jal     x0, hang
