-- Wire adapter only — the two policies above are the actual rules. Styled
-- after Yovico.Oracle.Whiteboard's real adapter: a state parser, a state
-- renderer, and a query evaluator that turns one line of input into one
-- line of hand-built JSON output. No JSON library — the protocol is small
-- enough that string concatenation is the honest choice, same call the
-- real adapter makes.
{-# OPTIONS --safe #-}
module Oracle where

open import Data.Bool.Base using (Bool; true; false)
open import Data.Maybe.Base using (Maybe; just; nothing)
open import Data.String.Base using (String; _++_)
open import Membership
open import AccessPolicy
open import BillingPolicy

stateP : String → Maybe MembershipState
stateP "active" = just active
stateP "cancelled_pending_period_end" = just cancelledPendingPeriodEnd
stateP "grace_period" = just gracePeriod
stateP "expired" = just expired
stateP _ = nothing

boolText : Bool → String
boolText true = "true"
boolText false = "false"

-- One line in, one line out: "<state>" → {"access_active":..,"billing_active":..}.
-- evaluate never needs the state back out again, so there is no stateText —
-- unlike Yovico.Oracle.Whiteboard's replay, which reports the state it
-- landed on after a sequence of events. A single-shot policy lookup has
-- nothing to replay.
evaluate : String → String
evaluate line with stateP line
... | nothing = "{\"error\":\"InvalidState\"}"
... | just s  = "{\"access_active\":" ++ boolText (AccessActive s) ++
                 ",\"billing_active\":" ++ boolText (BillingActive s) ++ "}"
