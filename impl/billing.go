package impl

// BillingActive mirrors spec/BillingPolicy.agda: is this member still
// being charged? The mirror image of AccessActive, not a copy of it. A
// cancelled member who's paid through period end owes nothing further; a
// member mid-retry after a failed charge is still on the hook until the
// retry resolves.
func BillingActive(s State) bool {
	switch s {
	case Active, GracePeriod:
		return true
	default:
		return false
	}
}
