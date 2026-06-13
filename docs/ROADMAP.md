# Project Roadmap

End goal: a synthesizable RISC-V CPU on FPGA, paired with an LLVM C toolchain,
a small OS, and an ML accelerator usable from ONNX / TFLite.

Tackle top-to-bottom. Each step should leave the design in a working, testable
state before moving on.

---

## 1. RISC-V CPU — pipelining (FPGA-targeted)

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
- [ ] Convert `instruction_memory.sv` to **synchronous read** (1-cycle latency,
      registered output) — that's how FPGA block RAM actually behaves.
- [ ] Convert `data_memory.sv` similarly (synchronous read, synchronous write).
- [ ] Adjust `fetch.sv` / `top.sv` so the existing single-cycle design still
      passes the regression suite with the new memory timing.

### 1.3 5-stage pipeline split
- [ ] Insert pipeline registers: `IF/ID`, `ID/EX`, `EX/MEM`, `MEM/WB`.
- [ ] No hazard handling yet. Verify on **no-hazard programs** (NOPs between
      dependent instructions) — proves the bones are right.
- [ ] Update schematic (`docs/schematic.drawio`) with the pipeline register
      stages.

### 1.4 Hazards
- [ ] **Data hazards — forwarding**: EX→EX and MEM→EX bypass paths for RAW.
- [ ] **Load-use hazard — stall**: 1-cycle bubble when load is followed by a
      dependent op.
- [ ] **Control hazards — branch flush**: assume-not-taken, kill IF/ID and ID/EX
      on misprediction. (Optional later: static BTFN or simple BTB.)
- [ ] Re-run full regression suite, all programs pass.

### 1.5 FPGA bring-up
- [ ] Pick target board / family (TBD — e.g., Xilinx Artix-7, Lattice ECP5).
- [ ] Replace `$readmemh` ROM with synthesizable BRAM init.
- [ ] Add a minimal top-level wrapper with clock, reset, and a debug output
      (e.g., LEDs from a memory-mapped register).
- [ ] Constraints file (clock, pins), report `Fmax` and slice/LUT usage.

---

## 2. LLVM C backend

- [ ] Stand up the off-the-shelf `riscv32-unknown-elf-gcc` / `clang` flow first
      as a reference — get a known-good binary running on the CPU.
- [ ] Define our linker script + memory layout (text in IMEM, data/stack in DMEM).
- [ ] Decide scope of custom LLVM backend: pure RV32I target, or RV32I + custom
      accelerator instructions (ties into step 4.1).
- [ ] Build LLVM out-of-tree backend skeleton (target description, register info,
      instruction info, calling convention).
- [ ] End-to-end: a hand-written `.c` file → custom LLVM → `.mem` → runs on CPU,
      diffed against gcc reference.

---

## 3. Operating System

- [ ] Add CSRs + privilege levels (M-mode at minimum, M+U for userspace).
- [ ] Trap/interrupt support: `mtvec`, `mepc`, `mcause`, `mtval`, `mstatus`.
- [ ] Timer interrupt (`mtime` / `mtimecmp`) — minimum hardware needed for a
      preemptive scheduler.
- [ ] Bare-metal "OS": boot, set up stack, install trap handler, cooperative
      multitasking demo.
- [ ] Stretch: simple round-robin scheduler, syscall via `ecall`,
      MMU/PMP for memory isolation.

---

## 4. RISC-V hardware accelerator

- [ ] Pick workload class (small NN inference: int8 matmul, conv kernel, etc.).
- [ ] Define custom instructions or memory-mapped accelerator interface.
  - Custom-0/Custom-1 opcode space if going ISA-extension route.
  - MMIO control + DMA if going coprocessor route.
- [ ] RTL for the accelerator (matrix-multiply unit / systolic array / etc.).
- [ ] Wire into pipeline (writeback path + stall logic if multi-cycle).
- [ ] Standalone tests, then full-system tests via memory-mapped registers.

### 4.1 LLVM backend for accelerator instructions
- [ ] Add intrinsics / builtins for the accelerator ops.
- [ ] Pattern-match C code (or explicit calls) to emit accelerator instructions.
- [ ] Performance benchmark: same kernel, scalar vs. accelerated.

---

## 5. ONNX EP or TFLite Delegate

- [ ] Decide ONNX Runtime Execution Provider vs. TFLite Delegate.
- [ ] Quantization story (likely int8) — must match accelerator data types.
- [ ] Op coverage plan: which ops run on accelerator, which fall back to CPU.
- [ ] Build the EP/delegate as a shared library that targets our toolchain.
- [ ] End-to-end demo: small model (e.g., MNIST CNN) running on the FPGA via
      the EP/delegate.

---

## Notes on ordering / parallelism

- Steps 1.1 and 1.2 unblock everything else and should be done first.
- Step 2 (LLVM) can start in parallel with step 1.3 once the regression
  harness exists, since the LLVM work is mostly off-FPGA.
- Step 3 (OS) needs CSRs in the CPU; do not start until step 1 is stable.
- Steps 4 and 5 are the long-tail and depend on a working pipelined CPU +
  toolchain.
