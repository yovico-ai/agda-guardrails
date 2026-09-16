---
name: spec-oracle
description: Builds a total Agda specification of a project's business rules or state machine and wires it, compiled to a native binary, as the live conformance oracle for a property-test suite in the implementation language (Go shown; any language with a property-testing library works). Use when a project has rules code must conform to — especially rules written down in a REQUIREMENTS.md, SPEC.md or PRD — and when adding, changing or reviewing such rules. Also use when asked for "spec as oracle", "executable specification", "formal spec for tests", "Agda spec" or "conformance testing".
license: MIT
compatibility: Requires Nix with flakes enabled (the bundled flake provisions Agda 2.8, agda-stdlib 2.3, GHC and Go), or an equivalent local Agda + GHC install.
metadata:
  author: yovico-ai
  version: "0.1"
  source: https://github.com/yovico-ai/agda-guardrails
---

# Spec as oracle

Turn the rules a system must follow into a **total** Agda specification —
one where the compiler refuses to build until every case is decided — then
compile that spec to a binary and have the implementation's property tests
ask it, live, what the correct answer is. The spec is not documentation
the code is compared against by eye; it is the test oracle.

This catches the class of bug where an implementation is internally
consistent, passes the tests its author thought to write, and still
disagrees with the person who asked for the feature.

## Non-negotiables

1. **A human owns the spec.** You may draft it from their requirements; you
   may not invent a rule. Every case the requirements do not decide becomes
   a question back to the human, never a default you picked. If you wrote
   both the spec and the code without a human reviewing the spec, the
   oracle proves nothing — say so rather than pretend otherwise.
2. **Total means total.** No wildcard `_` case in any domain function. Every
   constructor is matched by name so that adding one is a compile error
   everywhere a decision is now missing.
3. **`{-# OPTIONS --safe #-}` on every module that holds a rule.** Only the
   IO boundary (`Main.agda`) may omit it, because it needs one FFI call.
   Keep it free of logic so everything that matters is checked under
   `--safe`.
4. **One function per question.** "Is this member active?" is not one
   question if access and billing can disagree. Name the questions the
   business actually asks; never share one boolean between two of them.
5. **The vocabulary is checked, not asserted.** The implementation's copy of
   the state names and the spec's parser are hand-duplicated across two
   languages. The test suite asks the oracle for its own vocabulary at
   startup and refuses to run on mismatch.
6. **Show the oracle bite before you call it done.** Plant one wrong case in
   the implementation, watch the property test name the state and the
   function, revert. A test you never saw fail has proved nothing.

## Layout you are building

```
spec/
  <Domain>.agda        closed vocabulary: one data type, --safe
  <Question>.agda      one decision function per business question, --safe
  Oracle.agda          wire adapter: parse, print, evaluate, --safe
  Main.agda            IO boundary, verbatim from assets/example/spec/
  <name>.agda-lib      library file (3 lines, step 5)
harness/
  oracle_client.<ext>  one persistent oracle process, one line in, one out
  conformance_test.*   vocabulary handshake, then the property
impl/                  the code under test — knows nothing about spec/
flake.nix  Makefile  .github/workflows/ci.yml   from assets/
```

The worked example under `assets/example/` is a verbatim copy of a tested
reference implementation (a four-state membership domain, two questions:
access and billing). Read the file for the layer you are writing; adapt
the domain, keep the shape.

## Procedure

### 1. Source the rules — and surface the gaps

Look for `REQUIREMENTS.md`, `SPEC.md`, `docs/requirements*`, a PRD, or
ask. From it, extract:

- **The closed vocabulary.** The states (or events) the system can be in.
  Each is a constructor. If the document uses two words for one thing,
  ask which; if it uses one word for two things, split it and ask.
- **The questions.** Every yes/no (or small enum) decision the system makes
  about a state: "can they use the product", "are they still billed", "may
  this transition happen". Each is one function `State → Bool` (or `→ Enum`).
- **The truth table.** One row per state, one column per question.

Fill in only cells the document decides. Present the table with every
undecided cell marked `?`, like this:

```
state                          | AccessActive | BillingActive
-------------------------------|--------------|--------------
active                         | true         | true
cancelled_pending_period_end   | true         | false
grace_period                   | ?            | true
expired                        | false        | false
```

Stop here and get the `?` cells decided by the human. This is the step
where the requirements get debugged; Agda will refuse the spec until every
cell is filled, so fill them with answers, not guesses. If there is no
requirements document and the human cannot state the rules, stop — there
is nothing to specify.

### 2. Domain modules

One `data` type for the vocabulary (see `assets/example/spec/Membership.agda`),
then one module per question (`AccessPolicy.agda`, `BillingPolicy.agda`).
Each function matches every constructor by name. Comments say *why* a row
is what it is — the business reason — not what the code does.

### 3. Wire adapter — `Oracle.agda`

Follow `assets/example/spec/Oracle.agda` exactly; only the constructor
names and question names change. It has:

- `stateP : String → Maybe State` — parser, one literal pattern per state,
  `nothing` for anything else.
- `stateText : State → String` — printer.
- `allStates : List State` plus **two proofs**: `allStates-complete : ∀ s → s ∈ allStates`
  (coverage-checked — a new constructor fails to compile until listed) and
  `stateP-stateText : ∀ s → stateP (stateText s) ≡ just s` (parser and
  printer agree; each case is `refl`).
- `evaluate : String → String` — `"states"` answers
  `{"states":["...", ...]}`; any other line is parsed as a state and
  answers one JSON object with one boolean per question, or
  `{"error":"InvalidState"}`.

JSON is built by string concatenation on purpose: the protocol is a few
fields, and a JSON library is more code than trust here.

### 4. IO boundary — `Main.agda`

Copy `assets/example/spec/Main.agda` **verbatim**. It reads a line, writes
`evaluate line`, forever. It contains one postulate with a `COMPILE GHC`
pragma that sets stdout to line buffering — without it GHC block-buffers a
pipe, the first reply never leaves the process, and the whole protocol
hangs on query one. That is the only reason this file cannot be `--safe`.

### 5. Toolchain

Copy `assets/flake.nix`, `assets/Makefile`, and `assets/ci.yml` (to
`.github/workflows/ci.yml`). Add `spec/<name>.agda-lib`:

```
name: <name>
depend: standard-library
include: .
```

and to `.gitignore`: `/build/`, `/spec/_build/`, and the property-testing
library's replay directory (`/harness/testdata/` for rapid).

`nix develop` then `make check` runs everything. `make typecheck` alone is
the fast loop while writing Agda.

### 6. Harness client (implementation language)

Follow `assets/example/harness/oracle_client.go`. The shape that matters,
in any language:

- **One process for the whole test run**, started once, queries serialized
  with a mutex. A process per query makes a thousand-case run about process
  start-up, not the property.
- **Strip `LD_LIBRARY_PATH` from the child's environment** before exec. A
  nix-built binary links nix's glibc; an inherited path from CUDA or a venv
  shadows it and the child dies at start-up with an "undefined symbol".
- **Capture the child's stderr** and append it to any pipe error, so that
  crash names its cause instead of surfacing as "broken pipe".
- **Decode replies with presence checks.** In Go, pointer bools; in
  TypeScript, check `in`; in Python, `KeyError`. An `{"error":...}` reply
  must fail the query, never decode as two confident falses.
- **Kill the child on close**; the serve loop is `forever`, it will not
  notice EOF.
- Expose `States()` (the vocabulary query) and `Query(state)`.

### 7. Conformance test

Follow `assets/example/harness/conformance_property_test.go` and the
`AllStates` pattern in `assets/example/impl/membership.go`.

- In the suite's setup (`TestMain` in Go; a session fixture in pytest; a
  `beforeAll` in vitest): start the oracle, call `States()`, and require
  **set equality** with the implementation's own list of states. Fail the
  whole suite with `vocabulary drifted: spec knows [...], impl knows [...]`
  otherwise.
- The property: draw a state (rapid `SampledFrom`, fast-check
  `constantFrom`, hypothesis `sampled_from`), ask the oracle, compare
  **every** decision function. Report `Fn(state) = got, spec says want`.
- If the domain is a handful of states, say plainly in a comment that the
  "property test" is exhaustive in practice and a failure "after 0 tests"
  means the first draw. The shape earns its name once the input is an
  event *sequence* replayed by both sides; do not claim search you are not
  doing.

### 8. Prove it bites, then hand over

- Flip one case in one implementation function. `make check`. The property
  test must fail naming that state and that function. Revert.
- Add a constructor to the vocabulary without touching the questions.
  `make typecheck`. Agda must refuse with `Incomplete pattern matching`
  naming the first question in import order. Revert.
- Only then report done — and report both failures you just saw, with the
  exact output, so the human knows the oracle is live.

## Pitfalls, each one earned

| Symptom | Cause | Fix |
|---|---|---|
| First query hangs forever | GHC block-buffers stdout when it is a pipe | The `primSetLineBuffering` postulate in `Main.agda`; keep it |
| Child exits at start with `undefined symbol: __nptl_change_stack_perm` | Inherited `LD_LIBRARY_PATH` shadowing nix glibc | Strip it in the flake's `shellHook` **and** in the client before exec; if `nix develop` itself dies, `env -u LD_LIBRARY_PATH nix develop` |
| `compile: version 1.x.y does not match go tool version` | Inherited `GOROOT`/`GOPATH`, or `GOTOOLCHAIN=auto` reaching outside nix | The flake unsets them and sets `GOTOOLCHAIN=local` |
| `--safe` rejected on `Main.agda` | The FFI postulate | Correct — keep logic out of Main and `--safe` on everything else |
| Coverage error names a module you did not expect | Agda reports the first failure in import order | Read that one; the others follow |
| Oracle reply decoded as all-false | Decoding into plain bools | Presence-checked fields; treat `error` as a failed query |
| Property test "passes" on a broken implementation | The test never saw the oracle disagree | Step 8; never skip it |
| Vocabulary rename on one side only | Two hand-kept string lists | The `states` handshake in setup — it should have failed there |

## Done checklist

- [ ] Truth table reviewed by a human; no `?` cells remain, none were filled by you.
- [ ] Every rule module is `--safe`; no `_` pattern in any domain function.
- [ ] `Oracle.agda` has `allStates-complete` and `stateP-stateText`.
- [ ] `Main.agda` is verbatim from the example.
- [ ] Setup does the vocabulary handshake; the property compares every question.
- [ ] You saw the property test fail on a planted bug, and Agda refuse a fifth constructor, and reverted both.
- [ ] `make check` green; CI file in place.
- [ ] README states honestly how large the search space is.

## Reference

`assets/example/` mirrors https://github.com/yovico-ai/agda-guardrails,
whose `make check` refuses to pass if these copies drift from what its CI
tested. The repo's README walks the same domain end to end, including the
planted bug on its `broken` branch and the compile-time coverage demo.
