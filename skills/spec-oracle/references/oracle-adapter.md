# Agda side: domain modules and the wire adapter

Placeholders: `State` is your vocabulary type; `c1`, `c2` … its
constructors; `Q1`, `Q2` … your decision functions; `"c1"` the wire
spelling of `c1`; `"q1"` the JSON key for `Q1`. Rename those. Keep every
other line as written — each one is there because its absence was a bug
somewhere.

## Domain module — `spec/Domain.agda`

```agda
{-# OPTIONS --safe #-}
module Domain where

-- One constructor per state. The comment on each says what the state
-- means to the business, in the words the requirements use.
data State : Set where
  c1 : State
  c2 : State
```

## One module per question — `spec/Q1.agda`, `spec/Q2.agda`, …

```agda
{-# OPTIONS --safe #-}
module Q1 where

open import Data.Bool.Base using (Bool; true; false)
open import Domain

-- The comment gives the business reason for each row, not a paraphrase
-- of the code. Every constructor is matched by name: never `Q1 _ = …`,
-- or adding a state stops being a compile error here.
Q1 : State → Bool
Q1 c1 = true
Q1 c2 = false
```

## Wire adapter — `spec/Oracle.agda`

```agda
{-# OPTIONS --safe #-}
module Oracle where

open import Data.Bool.Base using (Bool; true; false)
open import Data.List.Base using (List; []; _∷_; map)
open import Data.List.Membership.Propositional using (_∈_)
open import Data.List.Relation.Unary.Any using (here; there)
open import Data.Maybe.Base using (Maybe; just; nothing)
open import Data.String.Base using (String; _++_; intersperse)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)
open import Domain
open import Q1
open import Q2

stateP : String → Maybe State
stateP "c1" = just c1
stateP "c2" = just c2
stateP _    = nothing

stateText : State → String
stateText c1 = "c1"
stateText c2 = "c2"

-- The oracle's own vocabulary, answered to a "states" query so the
-- harness can check its copy of these strings against the source. The
-- two proofs are what make the list trustworthy rather than one more
-- hand-kept copy.
allStates : List State
allStates = c1 ∷ c2 ∷ []

-- Coverage-checked: add a constructor and this stops compiling until
-- allStates lists it.
allStates-complete : ∀ s → s ∈ allStates
allStates-complete c1 = here refl
allStates-complete c2 = there (here refl)

-- Parser and printer agree on every spelling; each case is refl.
stateP-stateText : ∀ s → stateP (stateText s) ≡ just s
stateP-stateText c1 = refl
stateP-stateText c2 = refl

boolText : Bool → String
boolText true  = "true"
boolText false = "false"

quoted : String → String
quoted s = "\"" ++ s ++ "\""

-- One line in, one line out. "states" → the vocabulary; any other line
-- is parsed as a state and answered with one boolean per question, or
-- an error object the harness must treat as a failed query.
evaluate : String → String
evaluate "states" = "{\"states\":[" ++ intersperse "," (map quoted (map stateText allStates)) ++ "]}"
evaluate line with stateP line
... | nothing = "{\"error\":\"InvalidState\"}"
... | just s  = "{\"q1\":" ++ boolText (Q1 s) ++
                 ",\"q2\":" ++ boolText (Q2 s) ++ "}"
```

Notes:

- JSON by string concatenation is deliberate: a handful of fields, and a
  JSON library would be more code than trust.
- `"states"` is a reserved word on the wire; no state may be spelled that.
- Agda reports coverage errors in import order. Import the question
  modules in the order you want to read failures.
- If a question answers with a small enum rather than a boolean, give it
  its own `xText : Enum → String` and keep the same shape.

## Library file — `spec/<name>.agda-lib`

```
name: <name>
depend: standard-library
include: .
```

## IO boundary — `spec/Main.agda`

Copy `assets/Main.agda` verbatim. It is the only file that is not
`--safe`, for the one FFI call that sets line buffering; without it the
first reply never leaves the process.
