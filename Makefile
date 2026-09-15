.PHONY: check typecheck oracle test clean

AGDA ?= agda
GO ?= go
BUILD_DIR := build

# Full pipeline: typecheck the spec, compile it to the oracle binary,
# build the Go side, then run both the unit tests (impl/) and the
# property test that queries the oracle (harness/). On the `broken`
# branch this fails at the property-test step on purpose — see README.
check: typecheck oracle
	$(GO) build ./...
	$(GO) test ./impl/...
	ORACLE_BIN=$(CURDIR)/$(BUILD_DIR)/Main $(GO) test ./harness/... -v

# Main.agda imports Oracle.agda, which imports the three spec modules, so
# checking it alone checks the whole graph. Each module enforces its own
# --safe pragma individually (Membership/AccessPolicy/BillingPolicy/Oracle
# all declare it; Main.agda can't — it's the FFI-using IO boundary) — the
# same per-file discipline Yovico's own aggregate spec check uses.
typecheck:
	cd spec && $(AGDA) Main.agda

oracle: typecheck
	mkdir -p $(BUILD_DIR)
	cd spec && $(AGDA) --compile --ghc-flag=-O0 --compile-dir=$(CURDIR)/$(BUILD_DIR) Main.agda

clean:
	rm -rf $(BUILD_DIR) spec/_build
