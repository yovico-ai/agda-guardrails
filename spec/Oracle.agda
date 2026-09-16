-- Wire adapter only — the two policies above are the actual rules. Styled
-- after Yovico.Oracle.Whiteboard's real adapter: a state parser, a state
-- renderer, and a query evaluator that turns one line of input into one
-- line of hand-built JSON output. No JSON library — the protocol is small
-- enough that string concatenation is the honest choice, same call the
-- real adapter makes.
{-# OPTIONS --safe #-}
module Oracle where

open import Data.Bool.Base using (Bool; true; false)
open import Data.List.Base using (List; []; _∷_; map)
open import Data.List.Membership.Propositional using (_∈_)
open import Data.List.Relation.Unary.Any using (here; there)
open import Data.Maybe.Base using (Maybe; just; nothing)
open import Data.String.Base using (String; _++_; intersperse)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)
open import Membership
open import AccessPolicy
open import BillingPolicy

stateP : String → Maybe MembershipState
stateP "active" = just active
stateP "cancelled_pending_period_end" = just cancelledPendingPeriodEnd
stateP "grace_period" = just gracePeriod
stateP "expired" = just expired
stateP _ = nothing

stateText : MembershipState → String
stateText active                    = "active"
stateText cancelledPendingPeriodEnd = "cancelled_pending_period_end"
stateText gracePeriod               = "grace_period"
stateText expired                   = "expired"

-- The oracle's own vocabulary, answered to a "states" query so the Go
-- harness can check its copy of these strings against the source instead
-- of trusting a comment that says they match. On its own this would be
-- one more hand-kept list; the two proofs under it are what make it
-- trustworthy. Add a constructor to MembershipState and allStates-complete
-- stops compiling until allStates lists it; let stateP and stateText
-- disagree on a spelling and stateP-stateText stops compiling.
allStates : List MembershipState
allStates = active ∷ cancelledPendingPeriodEnd ∷ gracePeriod ∷ expired ∷ []

allStates-complete : ∀ s → s ∈ allStates
allStates-complete active                    = here refl
allStates-complete cancelledPendingPeriodEnd = there (here refl)
allStates-complete gracePeriod               = there (there (here refl))
allStates-complete expired                   = there (there (there (here refl)))

stateP-stateText : ∀ s → stateP (stateText s) ≡ just s
stateP-stateText active                    = refl
stateP-stateText cancelledPendingPeriodEnd = refl
stateP-stateText gracePeriod               = refl
stateP-stateText expired                   = refl

boolText : Bool → String
boolText true  = "true"
boolText false = "false"

quoted : String → String
quoted s = "\"" ++ s ++ "\""

-- One line in, one line out. "states" → {"states":[..]}; anything else is
-- taken as a state name → {"access_active":..,"billing_active":..}. Unlike
-- Yovico.Oracle.Whiteboard's replay, which reports the state it landed on
-- after a sequence of events, a single-shot policy lookup has nothing to
-- replay, so no query here ever renders a state back out except the
-- vocabulary listing.
evaluate : String → String
evaluate "states" = "{\"states\":[" ++ intersperse "," (map quoted (map stateText allStates)) ++ "]}"
evaluate line with stateP line
... | nothing = "{\"error\":\"InvalidState\"}"
... | just s  = "{\"access_active\":" ++ boolText (AccessActive s) ++
                 ",\"billing_active\":" ++ boolText (BillingActive s) ++ "}"
