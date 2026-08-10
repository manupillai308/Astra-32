# ============================================================
# RV32I CPU — regression harness
#
# Usage:
#   make build               compile RTL into Questa work library
#   make asm                 assemble all tests/*/*.s -> .mem
#   make run TEST=fibonacci  run one test, leaves actual_*.hex
#   make capture TEST=...    run + freeze actual as expected (golden)
#   make capture-all         run + freeze every test as expected
#   make test                run every test, diff against golden,
#                            print pass/fail summary
#   make clean               remove build artefacts
# ============================================================

SHELL := /bin/bash

# ---- Tooling -----------------------------------------------------
AS       := riscv64-unknown-elf-as
LD       := riscv64-unknown-elf-ld
OBJCOPY  := riscv64-unknown-elf-objcopy

ASFLAGS  := -march=rv32i -mabi=ilp32
LDFLAGS  := -m elf32lriscv -T tests/link.ld

VSIM     := vsim -c -voptargs="+acc" -do "run -all; quit"

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
	@od -An -tx1 -v -w4 tests/$(1)/$(1).bin > tests/$(1)/$(1).mem
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
	@rm -f tests/$(TEST)/actual_*.hex tests/$(TEST)/sim.log
	@$(VSIM) +PROGRAM=tests/$(TEST)/$(TEST).mem \
	         +OUTDIR=tests/$(TEST) \
	         work.test_bench

# ---- Capture: run then freeze actual_* as expected_* -------------
.PHONY: capture
capture: run
	@actuals=(tests/$(TEST)/actual_*.hex); \
	if [ "$${actuals[0]}" = "tests/$(TEST)/actual_*.hex" ]; then \
	  echo "[FAIL] no actual files produced for $(TEST)"; exit 1; \
	fi; \
	for actual in "$${actuals[@]}"; do \
	  expected=$${actual/actual_/expected_}; \
	  cp "$$actual" "$$expected"; \
	done
	@echo "[CAPTURED] $(TEST)"

.PHONY: capture-all
capture-all:
	@for t in $(TESTS); do \
	  $(MAKE) -s capture TEST=$$t || exit $$?; \
	done

# ---- Full regression ---------------------------------------------
# Runs every test, diffs against golden, prints pass/fail summary.
# Exits non-zero if any test fails (so CI can pick it up later).
.PHONY: test
test: build asm
	@pass=0; fail=0; failed=""; \
	for t in $(TESTS); do \
	  rm -f tests/$$t/actual_*.hex tests/$$t/sim.log; \
	  $(VSIM) +PROGRAM=tests/$$t/$$t.mem \
	          +OUTDIR=tests/$$t \
	          work.test_bench > tests/$$t/sim.log 2>&1; \
	  sim_status=$$?; \
	  ok=1; actual_count=0; \
	  if [ $$sim_status -ne 0 ]; then \
	    ok=0; \
	  fi; \
	  for actual in tests/$$t/actual_*.hex; do \
	    if [ "$$actual" = "tests/$$t/actual_*.hex" ]; then \
	      break; \
	    fi; \
	    actual_count=$$((actual_count+1)); \
	    expected=$${actual/actual_/expected_}; \
	    if [ ! -f "$$expected" ]; then \
	      echo "[MISSING] $$expected"; \
	      ok=0; \
	    elif ! diff -I '^//' -q "$$actual" "$$expected" >/dev/null 2>&1; then \
	      echo "[DIFF] $$actual $$expected"; \
	      ok=0; \
	    fi; \
	  done; \
	  for expected in tests/$$t/expected_*.hex; do \
	    if [ "$$expected" = "tests/$$t/expected_*.hex" ]; then \
	      break; \
	    fi; \
	    actual=$${expected/expected_/actual_}; \
	    if [ ! -f "$$actual" ]; then \
	      echo "[MISSING] $$actual"; \
	      ok=0; \
	    fi; \
	  done; \
	  if [ $$actual_count -eq 0 ]; then \
	    echo "[MISSING] tests/$$t/actual_*.hex"; \
	    ok=0; \
	  fi; \
	  if [ $$ok -eq 1 ]; then \
	    echo "[PASS] $$t"; pass=$$((pass+1)); \
	  else \
	    echo "[FAIL] $$t  (see tests/$$t/sim.log; diff actual vs expected)"; \
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
	rm -f  tests/*/actual_*.hex tests/*/sim.log
	rm -f  tests/*/*.o tests/*/*.elf tests/*/*.bin
	# .mem files are kept; remove with `make distclean` if desired

.PHONY: distclean
distclean: clean
	rm -f tests/*/*.mem
