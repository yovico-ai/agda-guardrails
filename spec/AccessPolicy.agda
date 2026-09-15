-- Whether this member can USE the product right now. A cancellation takes
-- effect at the end of the paid period, not the moment it's requested — so
-- a cancelled-but-still-in-period member keeps access. A member mid-retry
-- after a failed charge does not: the product doesn't wait to find out
-- whether the retry succeeds.
{-# OPTIONS --safe #-}
module AccessPolicy where

open import Data.Bool.Base using (Bool; true; false)
open import Membership

AccessActive : MembershipState → Bool
AccessActive active                    = true
AccessActive cancelledPendingPeriodEnd = true
AccessActive gracePeriod               = false
AccessActive expired                   = false
