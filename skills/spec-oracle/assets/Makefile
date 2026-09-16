.PHONY: check typecheck oracle clean

AGDA ?= agda
GO ?= go
BUILD_DIR := build

# Full pipeline: typecheck the spec, compile it to the oracle binary, build
# the implementation, run its own unit tests, then run the conformance
# property test that queries the compiled oracle.
check: typecheck oracle
	$(GO) build ./...
	$(GO) test ./impl/...
	ORACLE_BIN=$(CURDIR)/$(BUILD_DIR)/Main $(GO) test ./harness/... -v

# Main.agda imports the wire adapter, which imports every domain module, so
# checking it alone checks the whole graph. Each domain module carries its
# own --safe pragma; Main.agda cannot (it is the FFI-using IO boundary).
typecheck:
	cd spec && $(AGDA) Main.agda

# -O0: the oracle answers a few thousand one-line queries per test run;
# GHC optimisation buys nothing here and costs most of the build time.
oracle: typecheck
	mkdir -p $(BUILD_DIR)
	cd spec && $(AGDA) --compile --ghc-flag=-O0 --compile-dir=$(CURDIR)/$(BUILD_DIR) Main.agda

clean:
	rm -rf $(BUILD_DIR) spec/_build
