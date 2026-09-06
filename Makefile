# ============================================================
# RV32I CPU — regression harness
#
# Usage:
#   make build               compile RTL into Questa work library
#   make asm                 assemble all tests/*/*.s -> .mem
#   make run TEST=fibonacci  run one LED self-checking test
#   make test                run every LED self-checking test
#   make clean               remove build artefacts
# ============================================================

SHELL := /bin/bash

# ---- Tooling -----------------------------------------------------
AS       := riscv64-unknown-elf-as
LD       := riscv64-unknown-elf-ld
OBJCOPY  := riscv64-unknown-elf-objcopy

ASFLAGS  := -march=rv32i_zicsr -mabi=ilp32
LDFLAGS  := -m elf32lriscv -T tests/link.ld

VSIM     := vsim -c -voptargs="+acc" -do "run -all; quit"
SIM_TOP  := work.test_bench_data_memory

# ---- Sources -----------------------------------------------------
SRC      := $(wildcard src/*.sv)

# Each subdir of tests/ containing a .s file is a test.
TESTS    := $(notdir $(patsubst %/,%,$(dir $(wildcard tests/*/*.s))))

# ---- Default target ----------------------------------------------
.PHONY: all
all: test

# ---- Compile RTL -------------------------------------------------
# Always re-runs vlib (no-op if work/ exists) and vlog. Both are fast.
.PHONY: build
build:
	@vlib work 2>/dev/null || true
	@vlog -sv src/risc_pkg.sv $(SRC)

# ---- Assemble all .s -> .mem -------------------------------------
# Per-test rules generated via eval so dependency tracking works.
define ASM_template
tests/$(1)/$(1).mem: tests/$(1)/$(1).s tests/link.ld
	@$$(AS) $$(ASFLAGS) -o tests/$(1)/$(1).o tests/$(1)/$(1).s
	@$$(LD) $$(LDFLAGS) -o tests/$(1)/$(1).elf tests/$(1)/$(1).o
	@$$(OBJCOPY) -O binary tests/$(1)/$(1).elf tests/$(1)/$(1).bin
	@od -An -tx4 -v -w4 tests/$(1)/$(1).bin > tests/$(1)/$(1).mem
	@echo "[ASM]  $(1)"
endef
$(foreach t,$(TESTS),$(eval $(call ASM_template,$(t))))

.PHONY: asm
asm: $(foreach t,$(TESTS),tests/$(t)/$(t).mem)

# ---- Run a single test -------------------------------------------
.PHONY: run
run: build
	@if [ -z "$(TEST)" ]; then \
	  echo "Usage: make run TEST=<name>  (one of: $(TESTS))"; exit 1; \
	fi
	@$(MAKE) -s tests/$(TEST)/$(TEST).mem
	@rm -f tests/$(TEST)/sim.log
	@$(VSIM) +PROGRAM=tests/$(TEST)/$(TEST).mem $(SIM_TOP)

# ---- Full regression ---------------------------------------------
# Runs every LED self-checking test and prints pass/fail summary.
# Exits non-zero if any test fails (so CI can pick it up later).
.PHONY: test
test: build asm
	@pass=0; fail=0; failed=""; \
	for t in $(TESTS); do \
	  rm -f tests/$$t/sim.log; \
	  $(VSIM) +PROGRAM=tests/$$t/$$t.mem $(SIM_TOP) > tests/$$t/sim.log 2>&1; \
	  sim_status=$$?; \
	  ok=1; \
	  if [ $$sim_status -ne 0 ]; then \
	    ok=0; \
	  fi; \
	  if ! grep -q "\\[PASS\\]" tests/$$t/sim.log; then \
	    ok=0; \
	  fi; \
	  if [ $$ok -eq 1 ]; then \
	    echo "[PASS] $$t"; pass=$$((pass+1)); \
	  else \
	    echo "[FAIL] $$t  (see tests/$$t/sim.log)"; \
	    fail=$$((fail+1)); failed="$$failed $$t"; \
	  fi; \
	done; \
	echo "---------------------------------------------"; \
	echo "$$pass passed, $$fail failed"; \
	test $$fail -eq 0

# ---- Clean -------------------------------------------------------
.PHONY: clean
clean:
	rm -rf work transcript vsim.wlf
	rm -f  tests/*/sim.log
	rm -f  tests/*/*.o tests/*/*.elf tests/*/*.bin
	# .mem files are kept; remove with `make distclean` if desired

.PHONY: distclean
distclean: clean
	rm -f tests/*/*.mem
