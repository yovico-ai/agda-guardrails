// Package impl is the thing under test: a hand-written Go mirror of the
// Agda spec in spec/. Nothing here imports the spec or the oracle — that's
// the whole point. This package can drift from the rules it's supposed to
// implement, silently, the way any hand-written mirror of a spec can.
package impl

// State mirrors spec/Membership.agda's MembershipState. The string values
// are the wire vocabulary spec/Oracle.agda's stateP accepts. Nothing here
// can prove the two lists match, so the harness checks it at startup
// instead: it asks the compiled oracle for its own vocabulary and compares
// that to AllStates (see harness/conformance_property_test.go, TestMain).
type State string

const (
	Active                    State = "active"
	CancelledPendingPeriodEnd State = "cancelled_pending_period_end"
	GracePeriod               State = "grace_period"
	Expired                   State = "expired"
)

// AllStates is the generator's domain and this side of the vocabulary
// check. Go can't enumerate a type's constants, so this is kept by hand;
// the oracle handshake is what keeps it honest.
var AllStates = []State{Active, CancelledPendingPeriodEnd, GracePeriod, Expired}
