-- Whether this member is still being CHARGED right now. This is the
-- mirror image of AccessPolicy, not a copy of it: a cancelled member who's
-- paid through the period end owes nothing further, but a member mid-retry
-- after a failed charge is still on the hook — the retry might succeed —
-- so billing keeps them active exactly where access does not, and vice
-- versa. Every "active" callsite in a real product picks one of these two
-- functions, never a single shared boolean; collapsing them back into one
-- is the bug this whole repo demonstrates (see impl/membership.go on the
-- broken branch).
{-# OPTIONS --safe #-}
module BillingPolicy where

open import Data.Bool.Base using (Bool; true; false)
open import Membership

BillingActive : MembershipState → Bool
BillingActive active                    = true
BillingActive cancelledPendingPeriodEnd = false
BillingActive gracePeriod               = true
BillingActive expired                   = false
