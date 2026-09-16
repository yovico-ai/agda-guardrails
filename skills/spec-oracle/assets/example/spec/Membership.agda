-- The closed vocabulary this whole demo hangs off. Four states, on purpose
-- small enough to read in one sitting: a member is either paying normally,
-- winding down after a cancellation, mid-retry after a failed charge, or
-- gone. Everything downstream (AccessPolicy, BillingPolicy, the wire
-- adapter) pattern-matches this type exhaustively — no wildcard case
-- anywhere. Add a fifth constructor here without touching the two policy
-- modules and Agda's coverage checker refuses to compile; see
-- demo/add-paused-state.agda.patch.
{-# OPTIONS --safe #-}
module Membership where

data MembershipState : Set where
  active                    : MembershipState
  cancelledPendingPeriodEnd : MembershipState
  gracePeriod               : MembershipState
  expired                   : MembershipState
