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
directions. On the `broken` branch, `impl/billing.go` answers the billing
question with the access rule: a member is billed "for as long as their
membership is live", which sounds right, reads as deliberate, and is wrong
on exactly the two states where the policies diverge. Nothing about the
code looks off. Its unit tests pass. That's the whole bug — the kind that
gets written when the rule lives in someone's head instead of in a spec.

## Quickstart

```sh
git clone https://github.com/yovico-ai/agda-guardrails
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
    conformance_property_test.go:84: [rapid] failed after 1 tests: BillingActive("cancelled_pending_period_end") = true, spec says false
        To reproduce, specify -run="TestConformsToSpec" -rapid.seed=...
        Failed test output:
    conformance_property_test.go:85: [rapid] draw state: "cancelled_pending_period_end"
    conformance_property_test.go:96: BillingActive("cancelled_pending_period_end") = true, spec says false
--- FAIL: TestConformsToSpec (0.00s)
FAIL
```

(rapid draws randomly, so you may instead see it fail on `grace_period` —
the other state the two policies disagree on — and "after 1 tests" may
read "after 0 tests". Either way, `BillingActive` is the one that's
wrong.)

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

Same commands, everything green:

```
go test ./impl/...
ok      github.com/yovico-ai/agda-guardrails/impl

ORACLE_BIN=.../build/Main go test ./harness/... -v
=== RUN   TestConformsToSpec
    conformance_property_test.go:84: [rapid] OK, passed 100 tests (2.584641ms)
--- PASS: TestConformsToSpec (0.00s)
PASS
ok      github.com/yovico-ai/agda-guardrails/harness
```

The entire fix is one `case` list in `impl/billing.go`:

```sh
git diff main broken -- impl/billing.go
```

## Demonstration two, in slow motion: a spec-derived property test

`harness/oracle_client.go` compiles `spec/Main.agda` to a native binary
and keeps one instance running for the whole test — the property test in
`harness/conformance_property_test.go` asks it, for a randomly generated
state, what `AccessActive` and `BillingActive` should be, and compares
that against `impl`'s own functions. The spec isn't consulted for
documentation; it's queried, live, as the test oracle.

**On the word "property".** Four states is not a search space: rapid's
`SampledFrom` reaches all of them within its first few draws, so on this
domain the property test is an exhaustive check wearing a property test's
harness — which is why the failure above reports "after 1 tests", not
after thousands. What the repo demonstrates is the shape (generate, ask
the oracle, compare), not the search. The same `rapid.Check` against the
same oracle does real search once the input is an event *sequence*
instead of a state, which is what Yovico's own spec replays; this domain
is deliberately too small to need it.

**The vocabulary is checked, not asserted.** `impl.State`'s string values
and `spec/Oracle.agda`'s parser are hand-duplicated across two languages.
Rather than a comment promising they match, `TestMain` asks the compiled
oracle for its own list (a `states` query) and requires set equality with
`impl.AllStates` before any test runs. The oracle's side of that list
isn't taken on trust either: `Oracle.agda` carries two proofs,
`allStates-complete` (every constructor is in the list — coverage-checked,
so a fifth state won't compile until it's listed) and `stateP-stateText`
(parser and printer agree on every spelling). A rename on either side
fails up front as `vocabulary drifted: spec knows [...], impl knows [...]`,
not as an unexplained `InvalidState` in the middle of a run.

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
refuses to compile the spec at all. Try it (on either branch):

```sh
git apply demo/add-paused-state.agda.patch
make check
```

```
.../spec/AccessPolicy.agda:13.1-16.21: error: [CoverageIssue]
Incomplete pattern matching for AccessActive. Missing cases:
  AccessActive paused
```

Revert it (`git apply -R demo/add-paused-state.agda.patch`) and apply the
Go equivalent instead:

```sh
git apply demo/add-paused-state.go.patch
go build ./...
```

That succeeds. Nothing in Go's type system requires every `State`
constant to be handled anywhere a `switch` mentions the type, so the
existing `default: return false` in `impl/access.go` and `impl/billing.go`
silently absorbs `paused` — quietly deciding an access and billing
question nobody actually made. Same missing decision, two different
amounts of resistance. That gap is the entire argument, compiled.

(Add `Paused` to `impl.AllStates` as well and `make check` does catch it —
at the vocabulary handshake, because the spec doesn't know the word. That
is the spec catching it, not Go.)

## What it costs

Numbers from this repo, so the size of the demo is on the table:

- The domain spec — `Membership.agda`, `AccessPolicy.agda`,
  `BillingPolicy.agda` — is 52 lines. The wire adapter (`Oracle.agda`, 74
  lines, about a third of it the two vocabulary proofs) and the IO
  boundary (`Main.agda`, 42) bring the Agda side to 168. The Go harness is
  270 lines; the implementation under test, 54.
- `make check` from a cold build takes about 15 s on a developer machine,
  nearly all of it Agda type-checking and GHC compiling the oracle (48
  modules at `-O0`); the Go side runs in milliseconds. In GitHub Actions
  on `ubuntu-latest` with `magic-nix-cache`, the `make check` step is
  45 s.

## Use it in your own project

`skills/spec-oracle/` packages the method as an
[Agent Skill](https://agentskills.io): a `SKILL.md` an AI coding agent
loads when a task matches it, plus the generic plumbing (`flake.nix`,
`Makefile`, CI workflow) and a verbatim copy of this repo's spec and
harness as the worked example. The same folder works in Claude Code and
Codex; only the install path differs:

```sh
git clone https://github.com/yovico-ai/agda-guardrails

# Claude Code — per project, or ~/.claude/skills/ for every project
mkdir -p your-project/.claude/skills
cp -r agda-guardrails/skills/spec-oracle your-project/.claude/skills/

# Codex — per project, or ~/.agents/skills/ for every project
mkdir -p your-project/.agents/skills
cp -r agda-guardrails/skills/spec-oracle your-project/.agents/skills/
```

Then, in your project: "build a spec oracle for the rules in
REQUIREMENTS.md" (or `/spec-oracle` in Claude Code, `$spec-oracle` in
Codex). The skill's first step is to read your requirements document,
propose the closed vocabulary and the decision functions as a truth
table, and hand back every cell the document doesn't decide as a
question. Agda won't accept the spec until those cells are filled, so
they get filled with answers rather than defaults — the spec-writing step
is where the requirements get debugged. It then builds the layers in this
repo's order and refuses to call itself done until it has watched the
property test fail on a planted bug and Agda refuse a fifth state.

Two honest limits. The skill can't install Agda: the bundled flake does,
but Nix is still the entry fee. And an agent can draft the spec from your
requirements, but if nobody reviews it, the same model wrote both the
oracle and the code — so the skill says this out loud and stops for
review at the truth table.

The example under `skills/spec-oracle/assets/example/` is a copy of this
repo's own files; `make check` fails if they ever drift from what CI just
tested.

## What this is not

Not the real spec. Yovico's own product-tenancy and billing rules are
considerably larger and none of that content is here — this domain was
invented for this repo. What's real is the technique: a total Agda spec,
compiled to a binary, queried by a property test as the source of truth
for what "correct" means.

Not a general-purpose library. There's no reusable harness for wiring an
arbitrary Agda spec to an arbitrary Go (or TypeScript, or anything else)
test suite here. The skill above teaches an agent to rebuild the pattern
per project, which is deliberately not the same thing — nothing to
version, nothing to maintain. If a library is wanted, that's a different,
larger project.

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
