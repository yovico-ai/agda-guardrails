package impl

// AccessActive mirrors spec/AccessPolicy.agda: can this member use the
// product right now? A cancellation takes effect at the end of the paid
// period, not the moment it's requested, so a cancelled member keeps
// access until then. A member mid-retry after a failed charge does not —
// the product doesn't wait to find out whether the retry succeeds.
func AccessActive(s State) bool {
	switch s {
	case Active, CancelledPendingPeriodEnd:
		return true
	default:
		return false
	}
}
