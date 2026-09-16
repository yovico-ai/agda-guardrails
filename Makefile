.PHONY: check typecheck oracle test clean skill-check skill-sync

AGDA ?= agda
GO ?= go
BUILD_DIR := build

# Full pipeline: typecheck the spec, compile it to the oracle binary,
# build the Go side, then run both the unit tests (impl/) and the
# property test that queries the oracle (harness/). On the `broken`
# branch this fails at the property-test step on purpose — see README.
check: skill-check typecheck oracle
	$(GO) build ./...
	$(GO) test ./impl/...
	ORACLE_BIN=$(CURDIR)/$(BUILD_DIR)/Main $(GO) test ./harness/... -v

# skills/spec-oracle ships verbatim copies of these files as its worked
# example, so a reader can install the skill without cloning this repo.
# Copies drift; this refuses to pass until they match what CI just tested.
SKILL_EXAMPLE := skills/spec-oracle/assets/example
SKILL_VERBATIM := spec/Main.agda spec/Oracle.agda spec/Membership.agda \
  spec/AccessPolicy.agda spec/BillingPolicy.agda spec/agda-guardrails.agda-lib \
  harness/oracle_client.go harness/conformance_property_test.go impl/membership.go

skill-check:
	@for f in $(SKILL_VERBATIM); do \
	  cmp -s $$f $(SKILL_EXAMPLE)/$$f || { echo "$(SKILL_EXAMPLE)/$$f is out of date with $$f — run: make skill-sync"; exit 1; }; \
	done

skill-sync:
	@for f in $(SKILL_VERBATIM); do \
	  mkdir -p $(SKILL_EXAMPLE)/$$(dirname $$f) && cp $$f $(SKILL_EXAMPLE)/$$f; \
	done

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
