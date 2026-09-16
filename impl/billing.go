package impl

// BillingActive: is this member still being charged? Billing follows the
// membership itself — a member is billed for as long as their membership
// is live, whether that's paying normally or cancelled but still inside
// the period they've paid for.
func BillingActive(s State) bool {
	switch s {
	case Active, CancelledPendingPeriodEnd:
		return true
	default:
		return false
	}
}
