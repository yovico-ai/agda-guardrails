// Package impl is the thing under test: a hand-written Go mirror of the
// Agda spec in spec/. Nothing here imports the spec or the oracle — that's
// the whole point. This package can drift from the rules it's supposed to
// implement, silently, the way any hand-written mirror of a spec can.
package impl

// State mirrors spec/Membership.agda's MembershipState. Four states, kept
// in lockstep with the wire strings spec/Oracle.agda's stateP accepts —
// see harness/oracle_client.go.
type State string

const (
	Active                    State = "active"
	CancelledPendingPeriodEnd State = "cancelled_pending_period_end"
	GracePeriod               State = "grace_period"
	Expired                   State = "expired"
)

// AccessActive mirrors spec/AccessPolicy.agda: a cancellation takes effect
// at the end of the paid period, not the moment it's requested.
func AccessActive(s State) bool {
	switch s {
	case Active, CancelledPendingPeriodEnd:
		return true
	default:
		return false
	}
}

// BillingActive mirrors spec/BillingPolicy.agda: a member mid-retry after
// a failed charge is still on the hook until the retry resolves, so
// billing stays active exactly where access does not.
func BillingActive(s State) bool {
	switch s {
	case Active, GracePeriod:
		return true
	default:
		return false
	}
}
