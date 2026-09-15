// The property under test: for every membership state, impl's two
// decision functions must agree with the compiled Agda spec. Unlike
// membership_test.go's table of two "obvious" cases, this generates every
// state pgregory.net/rapid can reach from the type and checks all of
// them — the same idea as tenancy/preservation_property_test.go's
// rapid.Check(t, func(rt *rapid.T) {...}) shape, without that file's
// picker/rapidPicker/randPicker split: that abstraction exists there to
// draw from a large event space reproducibly across both rapid and a
// plain seeded generator; a four-constructor domain doesn't have enough
// space to earn it, so this uses rapid.SampledFrom directly.
package harness

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/yovico-ai/agda-guardrails/impl"
	"pgregory.net/rapid"
)

var oracle *Client

// TestMain keeps ONE compiled oracle process alive for every test in this
// package, the same reason the real specoracle.Client is a persistent
// child rather than a fresh process per query (see oracle_client.go).
func TestMain(m *testing.M) {
	path := os.Getenv("ORACLE_BIN")
	if path == "" {
		path = filepath.Join("..", "build", "Main")
	}
	c, err := Start(path)
	if err != nil {
		panic("start oracle (build it first — see README, `make oracle`): " + err.Error())
	}
	oracle = c
	code := m.Run()
	oracle.Close()
	os.Exit(code)
}

var allStates = []impl.State{
	impl.Active,
	impl.CancelledPendingPeriodEnd,
	impl.GracePeriod,
	impl.Expired,
}

// TestConformsToSpec is demonstration two from the README: on the broken
// branch this fails, naming the state and which policy disagreed, while
// TestAccessActive_ObviousCases and TestBillingActive_ObviousCases in
// impl/membership_test.go stay green throughout — the unit tests were
// never wrong, they just never asked about the two states where the two
// policies genuinely diverge.
func TestConformsToSpec(t *testing.T) {
	rapid.Check(t, func(rt *rapid.T) {
		s := rapid.SampledFrom(allStates).Draw(rt, "state")

		want, err := oracle.Query(string(s))
		if err != nil {
			rt.Fatalf("oracle query for %q: %v", s, err)
		}

		if got := impl.AccessActive(s); got != want.AccessActive {
			rt.Fatalf("AccessActive(%q) = %v, spec says %v", s, got, want.AccessActive)
		}
		if got := impl.BillingActive(s); got != want.BillingActive {
			rt.Fatalf("BillingActive(%q) = %v, spec says %v", s, got, want.BillingActive)
		}
	})
}
