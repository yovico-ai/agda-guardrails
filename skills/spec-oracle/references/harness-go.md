# Harness side (Go shown): oracle client and conformance test

Placeholders match `oracle-adapter.md`: `Q1`, `Q2` are your decision
functions, `"q1"`, `"q2"` their JSON keys, `impl` the package under test
with `type State string`, `AllStates []State`, and one `func Qn(State) bool`
per question. Lines marked `ADAPT` change; everything else stays.

## `harness/oracle_client.go`

```go
// Package harness drives the compiled Agda oracle. It transports requests
// and makes no decisions of its own.
package harness

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"sync"
)

// OracleResponse is the oracle's answer for one state. ADAPT: one field
// per question.
type OracleResponse struct {
	Q1 bool
	Q2 bool
}

// Client keeps ONE oracle process alive for the whole test run and
// serializes queries against it. A process per query would make a
// thousand-case run about process start-up, not the property.
type Client struct {
	mu     sync.Mutex
	cmd    *exec.Cmd
	stdin  io.WriteCloser
	stdout *bufio.Scanner
	stderr *bytes.Buffer
	closed bool
}

// Start launches the compiled oracle at path. Close kills it: the serve
// loop is `forever` and will not notice EOF.
func Start(path string) (*Client, error) {
	cmd := exec.Command(path)
	// A nix-built binary links nix's glibc; an inherited LD_LIBRARY_PATH
	// (CUDA, a venv, a version manager) can shadow it and the child dies at
	// start-up with "undefined symbol". Strip it before exec.
	cmd.Env = withoutLDLibraryPath(os.Environ())
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return nil, fmt.Errorf("oracle stdin pipe: %w", err)
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		_ = stdin.Close()
		return nil, fmt.Errorf("oracle stdout pipe: %w", err)
	}
	// Captured, not inherited, so a start-up crash names its cause instead
	// of surfacing as a bare "broken pipe".
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Start(); err != nil {
		_ = stdin.Close()
		return nil, fmt.Errorf("start oracle: %w", err)
	}
	return &Client{cmd: cmd, stdin: stdin, stdout: bufio.NewScanner(stdout), stderr: &stderr}, nil
}

func withoutLDLibraryPath(env []string) []string {
	out := make([]string, 0, len(env))
	for _, kv := range env {
		if strings.HasPrefix(kv, "LD_LIBRARY_PATH=") {
			continue
		}
		out = append(out, kv)
	}
	return out
}

// Close terminates the oracle. Safe to call more than once.
func (c *Client) Close() {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.closed {
		return
	}
	c.closed = true
	_ = c.stdin.Close()
	_ = c.cmd.Process.Kill()
	_ = c.cmd.Wait()
}

// States asks the oracle for its own vocabulary — every string its parser
// accepts. The suite compares this to impl.AllStates before running
// anything else.
func (c *Client) States() ([]string, error) {
	line, err := c.roundTrip("states")
	if err != nil {
		return nil, err
	}
	var r struct {
		States []string `json:"states"`
	}
	if err := json.Unmarshal([]byte(line), &r); err != nil || r.States == nil {
		return nil, fmt.Errorf("oracle protocol: unexpected reply to states query: %q", line)
	}
	return r.States, nil
}

// Query asks what every question decides for one state (wire form).
func (c *Client) Query(state string) (OracleResponse, error) {
	line, err := c.roundTrip(state)
	if err != nil {
		return OracleResponse{}, err
	}
	// Pointers, not bools: an {"error":...} reply must fail here, not
	// decode as a set of confident falses. ADAPT: one field per question.
	var r struct {
		Q1 *bool `json:"q1"`
		Q2 *bool `json:"q2"`
	}
	if err := json.Unmarshal([]byte(line), &r); err != nil || r.Q1 == nil || r.Q2 == nil {
		return OracleResponse{}, fmt.Errorf("oracle protocol: unexpected reply to %q: %q", state, line)
	}
	return OracleResponse{Q1: *r.Q1, Q2: *r.Q2}, nil
}

// roundTrip writes one line and reads one line back, serialized so two
// callers cannot interleave on the single pipe pair.
func (c *Client) roundTrip(req string) (string, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.closed {
		return "", fmt.Errorf("oracle client is closed")
	}
	if _, err := fmt.Fprintln(c.stdin, req); err != nil {
		return "", fmt.Errorf("write to oracle: %w%s", err, c.stderrSuffix())
	}
	if !c.stdout.Scan() {
		if err := c.stdout.Err(); err != nil {
			return "", fmt.Errorf("read from oracle: %w%s", err, c.stderrSuffix())
		}
		return "", fmt.Errorf("oracle closed its output%s", c.stderrSuffix())
	}
	return c.stdout.Text(), nil
}

func (c *Client) stderrSuffix() string {
	if c.stderr == nil || c.stderr.Len() == 0 {
		return ""
	}
	return fmt.Sprintf(" (oracle stderr: %s)", strings.TrimSpace(c.stderr.String()))
}
```

## `harness/conformance_test.go`

```go
package harness

import (
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"testing"

	"<module>/impl" // ADAPT
	"pgregory.net/rapid"
)

var oracle *Client

// One oracle process for every test in the package.
func TestMain(m *testing.M) {
	path := os.Getenv("ORACLE_BIN")
	if path == "" {
		path = filepath.Join("..", "build", "Main")
	}
	c, err := Start(path)
	if err != nil {
		fmt.Fprintln(os.Stderr, "start oracle (build it first: make oracle):", err)
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

// The abstraction function between impl.State and the spec's State,
// checked rather than asserted: the two sides' strings are hand-kept in
// two languages, and a comment saying they match is not evidence.
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

// For every state, every decision function agrees with the compiled spec.
func TestConformsToSpec(t *testing.T) {
	rapid.Check(t, func(rt *rapid.T) {
		s := rapid.SampledFrom(impl.AllStates).Draw(rt, "state")

		want, err := oracle.Query(string(s))
		if err != nil {
			rt.Fatalf("oracle query for %q: %v", s, err)
		}

		// ADAPT: one comparison per question. Report got vs. spec.
		if got := impl.Q1(s); got != want.Q1 {
			rt.Fatalf("Q1(%q) = %v, spec says %v", s, got, want.Q1)
		}
		if got := impl.Q2(s); got != want.Q2 {
			rt.Fatalf("Q2(%q) = %v, spec says %v", s, got, want.Q2)
		}
	})
}
```

`impl` needs, next to its constants:

```go
// Go cannot enumerate a type's constants, so this is kept by hand; the
// oracle handshake in TestMain is what keeps it honest.
var AllStates = []State{C1, C2}
```

Add the property-testing library's replay directory to `.gitignore`
(`/harness/testdata/` for rapid).

## Other languages

Same shape, different spelling. Persistent child process with a mutex or
a single async queue; strip `LD_LIBRARY_PATH` from the child's env;
capture stderr; decode with presence checks (`"q1" in obj` in
TypeScript, `obj["q1"]` raising `KeyError` in Python — never `.get` with
a default); vocabulary handshake in a `beforeAll` / session fixture;
property with fast-check `constantFrom` or hypothesis `sampled_from`.
