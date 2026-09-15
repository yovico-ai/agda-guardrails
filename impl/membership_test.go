package impl

import "testing"

// These are the two cases anyone writing this code would think to test:
// a normal paying member, and a member who's fully gone. Both policies
// agree on both of these states, which is exactly why they don't catch
// the bug — see harness/conformance_property_test.go for the two states
// where AccessActive and BillingActive genuinely disagree.

func TestAccessActive_ObviousCases(t *testing.T) {
	if !AccessActive(Active) {
		t.Error("an active member should have access")
	}
	if AccessActive(Expired) {
		t.Error("an expired member should not have access")
	}
}

func TestBillingActive_ObviousCases(t *testing.T) {
	if !BillingActive(Active) {
		t.Error("an active member should be billed")
	}
	if BillingActive(Expired) {
		t.Error("an expired member should not be billed")
	}
}
