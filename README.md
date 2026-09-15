# agda-guardrails

A runnable answer to one claim: a formal spec can act as an executable
oracle for AI-agent-generated code, catching the class of bug where an
implementation is internally consistent, passes its own tests, and still
disagrees with the person who asked for the feature.

This repo doesn't argue that. It demonstrates it, on a domain small enough
to read in two minutes, with a compiler and a property test doing the
talking instead of prose.

## The domain

A membership has four states:

- `active` — paying normally.
- `cancelled_pending_period_end` — cancelled, but paid through the end of
  the period.
- `grace_period` — a charge failed; still inside the retry window.
- `expired` — gone.

Two policies decide, independently, whether a member is "active":

- **Access** — can they use the product right now? A cancellation takes
  effect at period end, not the moment it's requested, so a cancelled
  member keeps access until then.
- **Billing** — are they still being charged? A member in the retry
  window is still on the hook until the retry resolves, so billing stays
  active exactly where access has already stopped — and vice versa for
  the cancelled case.

The two policies disagree on two of the four states, in opposite
directions. A single, shared `IsActive()` boolean — the natural first cut
almost anyone would write — cannot represent that. That's the whole bug.

## Quickstart

```sh
git clone <this repo>
cd agda-guardrails
nix develop
make check
```

You're on `broken`, this repo's default branch. `make check` type-checks
the spec, compiles it to a binary, builds the Go implementation, and runs
both test layers. Expect this:

```
go test ./impl/...
ok      github.com/yovico-ai/agda-guardrails/impl

ORACLE_BIN=.../build/Main go test ./harness/... -v
=== RUN   TestConformsToSpec
    conformance_property_test.go:61: AccessActive("cancelled_pending_period_end") = false, spec says true
--- FAIL: TestConformsToSpec (0.00s)
FAIL
```

`impl/membership_test.go`'s unit tests are green. They were never wrong —
they cover the two states anyone would think to test (`active`,
`expired`), where both policies happen to agree. `harness/conformance_property_test.go`
generates all four states and checks both policies against the compiled
spec; it's the one that finds the states nobody wrote a test for.

Now look at the fix:

```sh
git checkout main
make check
```

Same commands, everything green: `impl/membership.go` on this branch has
two separate functions, `AccessActive` and `BillingActive`, instead of
one collapsed boolean. Diff the two branches' `impl/membership.go` to see
the entire fix — it's a few lines.

## Demonstration two, in slow motion: a spec-derived property test

`harness/oracle_client.go` compiles `spec/Main.agda` to a native binary
and keeps one instance running for the whole test — the property test in
`harness/conformance_property_test.go` asks it, for a randomly generated
state, what `AccessActive` and `BillingActive` should be, and compares
that against `impl`'s own functions. The spec isn't consulted for
documentation; it's queried, live, as the test oracle.

This is a small, invented-domain rebuild of a real pattern already
running inside Yovico's own product spec (`spec/OracleMain.agda` there,
not here) — compile the spec, talk to it over stdin/stdout, generate
inputs and check conformance. This repo strips it down: no request IDs,
no build-digest check, no host process multiplexing several domains —
just one compiled binary answering one kind of question, because a
four-state demo has nothing to correlate or version.

## Demonstration one: what "total" buys you at compile time

Both `AccessPolicy.agda` and `BillingPolicy.agda` pattern-match
`MembershipState` exhaustively — no wildcard `_` case anywhere. Add a
fifth state without touching either policy, and Agda's coverage checker
refuses to compile the spec at all. Try it:

```sh
git apply demo/add-paused-state.agda.patch
make check
```

```
Checking AccessPolicy (.../spec/AccessPolicy.agda).
error: Incomplete pattern matching for AccessActive.
Missing cases:
    AccessActive paused
```

Revert it (`git checkout spec/Membership.agda`) and apply the Go
equivalent instead:

```sh
git apply demo/add-paused-state.go.patch
go build ./...
```

That succeeds. Nothing in Go's type system requires every `State`
constant to be handled anywhere a `switch` mentions the type, so
`AccessActive`/`BillingActive`'s existing `default: return false` silently
absorbs `paused` — quietly deciding an access and billing question nobody
actually made. Same missing decision, two different amounts of
resistance. That gap is the entire argument, compiled.

## What this is not

Not the real spec. Yovico's own product-tenancy and billing rules are
considerably larger and none of that content is here — this domain was
invented for this repo. What's real is the technique: a total Agda spec,
compiled to a binary, queried by a property test as the source of truth
for what "correct" means.

Not a general-purpose library. There's no reusable harness for wiring an
arbitrary Agda spec to an arbitrary Go (or TypeScript, or anything else)
test suite here — just this one demo's worth of glue. If that's wanted as
a real tool, that's a different, larger project.

## Requirements

Nix with flakes enabled. `nix develop` provisions Agda 2.8 + the standard
library, GHC (Agda's compile backend), and Go — nothing else to install.

**If `nix develop` itself crashes** with
`undefined symbol: __nptl_change_stack_perm`, an `LD_LIBRARY_PATH` your
shell already exports (CUDA, a Python venv, a Go version manager) is
shadowing the nix-built glibc these tools link against, and it happens
before the flake's own shell can strip it. Run
`env -u LD_LIBRARY_PATH nix develop` instead.

## License

MIT. See [LICENSE](LICENSE).

---

Built by [Yovico](https://www.yovico.ai) to accompany
["The Equation and AI"](https://www.yovico.ai/blog/the-equation-and-ai/).
