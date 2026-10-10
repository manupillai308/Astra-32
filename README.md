# RISC-V FPGA SoC

This project is a small RISC-V SoC built to run Linux on an FPGA.

The goal is not to build the fastest processor. The goal is to keep the CPU,
memory system, peripherals, and boot process simple enough to study while
still building a complete Linux-capable system.

The current core implements **RV32IM_Zicsr_Zifencei** and supports machine,
supervisor, and user privilege modes.

> This is still a work in progress. It does not boot Linux yet.

## Features

### CPU

- [x] RV32I base instruction set
- [x] Five-stage pipeline
- [x] Register forwarding
- [x] Load-use hazard detection
- [x] Branch, trap, and interrupt pipeline flushing
- [x] Multi-cycle memory and execution stalls
- [x] RV32M multiply, divide, and remainder instructions
- [x] Zicsr CSR instructions
- [x] `FENCE` and `FENCE.I`

### Privilege and Traps

- [x] Machine, supervisor, and user modes
- [x] Machine and supervisor CSRs
- [x] Synchronous exceptions
- [x] Precise trap entry and return
- [x] `ECALL`, `EBREAK`, `MRET`, and `SRET`
- [x] Trap and interrupt delegation
- [x] Software, timer, and external interrupt CSR paths
- [x] RISC-V interrupt priority handling
- [x] Counter CSRs and privilege-based counter access

### Memory System

- [x] Separate instruction and data interfaces
- [x] Valid/ready/response memory handshakes
- [x] Boot ROM
- [x] BRAM-backed simulation memory
- [x] Shared memory arbitration between instruction and data requests
- [x] Xilinx MIG DDR3 interface
- [x] CPU-to-DDR clock-domain crossing
- [x] Instruction fetch and data access from DDR-backed RAM
- [x] Byte, half-word, and word memory operations

### SoC Peripherals

- [x] Address-decoded system bus
- [x] Memory-mapped LED register
- [x] UART transmitter and status register
- [x] CLINT-style `mtime`, `mtimecmp`, and software interrupts
- [x] FPGA clock and reset integration

### Verification

- [x] Directed assembly regression suite
- [x] Self-checking LED pass/fail convention
- [x] BRAM-backed Questa testbench
- [x] DDR3-backed Vivado/XSim testbench
- [x] Vivado Tcl regression runner
- [x] Tests for hazards, memory operations, traps, privilege modes, interrupts,
      fences, DDR access, and RV32M

## Development Environment

The included [dev container](.devcontainer/devcontainer.json) builds from
`.devcontainer/Dockerfile` and provides the RISC-V GNU toolchain, Make,
Verilator, Icarus Verilog, GTKWave, and Yosys on Ubuntu 24.04.

Open the repository in VS Code and select **Dev Containers: Reopen in
Container** to build and enter the environment.

Questa and Vivado are not installed by the Dockerfile. Questa must be made
available to the container to run the Makefile simulations. Vivado and the MIG
simulation flow are run separately on the host system.

## Quick Start

Run the following commands from the development container after making Questa
available:

```sh
# Assemble all tests
make asm

# Run one test
make run TEST=smoke

# Run the full BRAM-backed test suite
make test
```

DDR3 simulation depends on the generated Xilinx MIG IP and DDR3 model, so it is
run through Vivado using the Tcl regression script in `xilinx_project/`.

## Repository Layout

```text
.devcontainer/    Reproducible toolchain environment
src/              CPU, bus, memories, peripherals, and testbenches
tests/            Directed assembly tests
xilinx_project/   Vivado project and XSim test runner
docs/             Design notes and detailed roadmap
Makefile          Assembly and Questa test flow
```

The main FPGA design is organized as follows:

```text
fpga_top
`-- top
    |-- cpu
    `-- bus
        |-- boot ROM
        |-- DDR memory interface
        |-- CLINT
        |-- UART
        `-- LED MMIO
```

`top_data_memory` and `test_bench_data_memory` provide a faster BRAM-backed
configuration for the regular regression suite. The main `top` design uses the
DDR memory interface intended for the FPGA.

## Pending Work

- [ ] RV32A atomic extension
- [ ] Sv32 virtual memory and memory protection
- [ ] Remaining platform peripherals and interrupts
- [ ] Firmware and boot flow
- [ ] OpenSBI and Linux bring-up
- [ ] Caches and performance work

Floating point is not required for the initial Linux bring-up. The first Linux
target will use a soft-float kernel and userspace.

More detailed implementation notes are kept in
[`docs/ROADMAP.md`](docs/ROADMAP.md).
