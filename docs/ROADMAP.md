# Project Roadmap

End goal: a synthesizable RISC-V SoC on FPGA that can first run bare-metal
programs, then a small OS, then a Linux-capable RISC-V system, paired with an
LLVM C toolchain and an ML accelerator usable from ONNX / TFLite.

Tackle top-to-bottom. Each step should leave the design in a working, testable
state before moving on.

---

## 1. RISC-V CPU — pipelining (FPGA-targeted)

Current ISA scope: **RV32I**. The assembler flow uses
`-march=rv32i -mabi=ilp32`, and the RTL currently decodes RV32I integer
compute, load/store, branch, jump, `LUI`, and `AUIPC` instructions.

### 1.1 Foundations before touching the pipeline
- [x] **Regression harness**
  - Script that compiles `src/*.sv`, runs each `.mem` program through
    `test_bench.sv`, dumps final register file + data memory.
  - Golden reference: hand-computed or captured-once-and-frozen outputs for
    `find_maximum_in_array`, `fibonacci_sequence`, `bubble_sort`.
  - Pass/fail diff on every run; must stay green through every pipeline change.
- [x] **Early synthesis check**
  - Add `make synth` (yosys) that runs over `src/*.sv` and reports cell counts +
    any inferred latches. Catch FPGA-unfriendly constructs early.

### 1.2 Memory model matching real FPGA BRAM
- [x] Convert `instruction_memory.sv` to **synchronous read** (1-cycle latency,
      registered output) — that's how FPGA block RAM actually behaves.
- [x] Convert `data_memory.sv` similarly (synchronous read, synchronous write).
- [x] Adjust `fetch.sv` / `top.sv` so the existing single-cycle design still
      passes the regression suite with the new memory timing.

### 1.3 5-stage pipeline split
- [x] Insert pipeline registers: `IF/ID`, `ID/EX`, `EX/MEM`, `MEM/WB`.
- [x] No hazard handling yet. Verify on **no-hazard programs** (NOPs between
      dependent instructions) — proves the bones are right.
- [x] Update schematic (`docs/schematic.drawio`) with the pipeline register
      stages.

### 1.4 Hazards
- [x] **Data hazards — forwarding**: EX→EX and MEM→EX bypass paths for RAW.
- [x] **Load-use hazard — stall**: 1-cycle bubble when load is followed by a
      dependent op.
- [x] **Control hazards — branch flush**: assume-not-taken, kill IF/ID and ID/EX
      on misprediction. (Optional later: static BTFN or simple BTB.)
- [x] Re-run full regression suite, all programs pass.

### 1.5 FPGA bring-up
- [x] Pick target board / family (TBD — e.g., Xilinx Artix-7, Lattice ECP5).
- [ ] Replace `$readmemh` ROM with synthesizable BRAM init.
- [x] Add a minimal top-level wrapper with clock, reset, and a debug output
      (e.g., LEDs from a memory-mapped register).
- [ ] Constraints file (clock, pins), report `Fmax` and slice/LUT usage.

---

## 2. Linux-Capable SoC Bring-Up Path

Linux is not just "more instructions"; it needs a platform. Build this in
small, testable SoC steps after basic FPGA bring-up.

### 2.1 Clean SoC structure
- [x] Split the CPU core from the SoC wrapper: `cpu` is the core, `top` is the
      SoC, and `fpga_top` is the board wrapper.
- [x] Add a simple bus/address decoder for RAM vs. MMIO.
- [x] Add first MMIO peripheral: software-controlled LED register.
- [ ] Define and document the physical memory map in one place:
      RAM, boot ROM, UART, timer, interrupt controller, and future devices.
- [ ] Add unmapped-address behavior: return zero for reads for now; later raise
      a load/store access fault when traps exist.

### 2.2 Minimum useful FPGA SoC
- [ ] Replace tiny internal RAM with a larger RAM target appropriate for the
      board: BRAM first, then external DDR if available.
- [ ] Add a boot ROM or fixed reset image that can jump into RAM.
- [ ] Add UART MMIO for console output/input. This becomes the primary hardware
      debug path; LEDs are only bring-up visibility.
- [ ] Add a machine timer (`mtime` / `mtimecmp`) and expose it through MMIO.
- [ ] Add a basic interrupt path from peripherals into the CPU.

### 2.3 ISA and privilege work for OS/Linux
- [ ] Add `Zicsr`: CSR read/write instructions.
- [ ] Add `Zifencei`: instruction-fetch fence support.
- [ ] Add machine-mode CSRs and traps: `mstatus`, `mtvec`, `mepc`, `mcause`,
      `mtval`, `mie`, `mip`, `mscratch`.
- [ ] Add `ecall`, `ebreak`, `mret`, and precise exception entry/return.
- [ ] Add supervisor mode and supervisor CSRs: `sstatus`, `stvec`, `sepc`,
      `scause`, `stval`, `satp`, `sie`, `sip`, plus delegation CSRs.
- [ ] Add virtual memory with Sv32 page-table translation and TLB behavior.
- [ ] Add the `A` extension or an equivalent atomic path. Linux needs atomic
      operations for locks and kernel synchronization.
- [ ] Add the `M` extension (`mul`, `div`, remainder). Linux can theoretically
      trap/emulate missing integer multiply/divide, but implementing `M` is the
      practical target.

### 2.4 FPU decision
- [ ] Do **not** treat FPU as the first Linux blocker. A soft-float Linux/userland
      target can run without hardware `F`/`D`.
- [ ] Decide later whether to implement `F` and `D` for a standard hard-float
      userspace ABI and better application performance.
- [ ] If `F`/`D` are added, also implement floating-point CSRs, context-switch
      state, exception flags, and tests.

### 2.5 Linux bring-up milestones
- [ ] Run progressively richer bare-metal firmware from the SoC memory map.
- [ ] Run a tiny machine-mode monitor or SBI-like firmware layer.
- [ ] Boot a minimal supervisor-mode payload.
- [ ] Boot a Linux kernel with an initramfs over UART console.
- [ ] Add a device tree that describes RAM, CPU ISA string, UART, timer,
      interrupt controller, and memory map accurately.

---

## 3. LLVM C backend

- [ ] Stand up the off-the-shelf `riscv32-unknown-elf-gcc` / `clang` flow first
      as a reference — get a known-good binary running on the CPU.
- [ ] Define our linker script + memory layout (text in IMEM, data/stack in DMEM).
- [ ] Decide scope of custom LLVM backend: pure RV32I target, or RV32I + custom
      accelerator instructions (ties into step 5.1).
- [ ] Build LLVM out-of-tree backend skeleton (target description, register info,
      instruction info, calling convention).
- [ ] End-to-end: a hand-written `.c` file → custom LLVM → `.mem` → runs on CPU,
      diffed against gcc reference.

---

## 4. Operating System

- [ ] Add CSRs + privilege levels (M-mode at minimum, M+U for userspace).
- [ ] Trap/interrupt support: `mtvec`, `mepc`, `mcause`, `mtval`, `mstatus`.
- [ ] Timer interrupt (`mtime` / `mtimecmp`) — minimum hardware needed for a
      preemptive scheduler.
- [ ] Bare-metal "OS": boot, set up stack, install trap handler, cooperative
      multitasking demo.
- [ ] Stretch: simple round-robin scheduler, syscall via `ecall`,
      MMU/PMP for memory isolation.

---

## 5. RISC-V hardware accelerator

- [ ] Pick workload class (small NN inference: int8 matmul, conv kernel, etc.).
- [ ] Define custom instructions or memory-mapped accelerator interface.
  - Custom-0/Custom-1 opcode space if going ISA-extension route.
  - MMIO control + DMA if going coprocessor route.
- [ ] RTL for the accelerator (matrix-multiply unit / systolic array / etc.).
- [ ] Wire into pipeline (writeback path + stall logic if multi-cycle).
- [ ] Standalone tests, then full-system tests via memory-mapped registers.

### 5.1 LLVM backend for accelerator instructions
- [ ] Add intrinsics / builtins for the accelerator ops.
- [ ] Pattern-match C code (or explicit calls) to emit accelerator instructions.
- [ ] Performance benchmark: same kernel, scalar vs. accelerated.

---

## 6. ONNX EP or TFLite Delegate

- [ ] Decide ONNX Runtime Execution Provider vs. TFLite Delegate.
- [ ] Quantization story (likely int8) — must match accelerator data types.
- [ ] Op coverage plan: which ops run on accelerator, which fall back to CPU.
- [ ] Build the EP/delegate as a shared library that targets our toolchain.
- [ ] End-to-end demo: small model (e.g., MNIST CNN) running on the FPGA via
      the EP/delegate.

---

## Notes on ordering / parallelism

- Steps 1.1 and 1.2 unblock everything else and should be done first.
- Step 2 starts after FPGA bring-up because it depends on a stable SoC boundary
  and a physical memory map.
- Step 3 (LLVM) can start in parallel with step 1.3 once the regression
  harness exists, since the LLVM work is mostly off-FPGA.
- Step 4 (small OS) needs CSRs in the CPU; do not start until step 1 is stable.
- Linux bring-up needs Step 2.3 substantially complete: privilege, traps,
  timer/interrupts, atomics, and Sv32 MMU.
- Steps 5 and 6 are the long-tail and depend on a working pipelined CPU,
  SoC memory map, and toolchain.
