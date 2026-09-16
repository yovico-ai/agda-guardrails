// The property under test: for every membership state, impl's two
// decision functions must agree with the compiled Agda spec.
//
// An honest note on the word "property": with four states,
// rapid.SampledFrom reaches all of them within its first few draws, so
// this is an exhaustive check wearing a property test's harness — which
// is why a failure here reports "after 0 tests" rather than after
// thousands. What's being demonstrated is the shape, not the search: the
// same rapid.Check against the same oracle does real search once the
// input is an event sequence instead of a state, which is what Yovico's
// own spec replays (its tenancy/preservation_property_test.go has a
// picker/rapidPicker/randPicker split purely to draw reproducibly from
// that much larger space). A four-constructor domain doesn't have the
// space to earn any of that.
package harness

import (
	"fmt"
	"os"
	"path/filepath"
	"slices"
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
		fmt.Fprintln(os.Stderr, "start oracle (build it first — see README, `make oracle`):", err)
		os.Exit(1)
	}
	if err := checkVocabulary(c); err != nil {
		c.Close()
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	oracle = c
	code := m.Run()
	oracle.Close()
	os.Exit(code)
}

// checkVocabulary is the abstraction function between impl.State and
// spec/Membership.agda's MembershipState, checked rather than asserted.
// The two sides' strings are hand-duplicated across two languages, and a
// comment saying they match is not evidence: the oracle answers a
// "states" query with its own list (proved complete in Oracle.agda) and
// it has to equal impl.AllStates as a set, or nothing else runs.
func checkVocabulary(c *Client) error {
	specStates, err := c.States()
	if err != nil {
		return fmt.Errorf("oracle vocabulary: %w", err)
	}
	implStates := make([]string, len(impl.AllStates))
	for i, s := range impl.AllStates {
		implStates[i] = string(s)
	}
	slices.Sort(specStates)
	slices.Sort(implStates)
	if !slices.Equal(specStates, implStates) {
		return fmt.Errorf("vocabulary drifted: spec knows %v, impl knows %v", specStates, implStates)
	}
	return nil
}

// TestConformsToSpec is demonstration two from the README: on the broken
// branch this fails, naming the state and which policy disagreed, while
// TestAccessActive_ObviousCases and TestBillingActive_ObviousCases in
// impl/membership_test.go stay green throughout — the unit tests were
// never wrong, they just never asked about the two states where the two
// policies genuinely diverge.
func TestConformsToSpec(t *testing.T) {
	rapid.Check(t, func(rt *rapid.T) {
		s := rapid.SampledFrom(impl.AllStates).Draw(rt, "state")

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
