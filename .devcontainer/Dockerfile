FROM --platform=linux/amd64 ubuntu:24.04

RUN apt-get update && apt-get install -y \
    git make cmake gcc g++ python3 \
    verilator iverilog gtkwave yosys nano gcc-riscv64-unknown-elf \
    && rm -rf /var/lib/apt/lists/*