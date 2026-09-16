// Package harness drives the compiled Agda oracle (spec/Main.agda) from
// Go. It transports requests; it makes no decisions of its own. Shaped
// after Yovico's real services/engine-go/internal/specoracle/client.go,
// simplified for a single-oracle demo: no request IDs, no build-digest
// check, no Node host in front of the binary — this talks to the compiled
// executable directly over one newline-delimited line per query, because
// a four-state demo has nothing to correlate or version.
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

// OracleResponse is spec/Oracle.agda's answer for one state.
type OracleResponse struct {
	AccessActive  bool
	BillingActive bool
}

// Client keeps one compiled oracle process alive for the life of a test
// run and serializes queries against it. The real specoracle.Client does
// the same for the same reason: a fresh process per query would make a
// rapid.Check run with thousands of cases dominated by process-start
// overhead rather than the property itself.
type Client struct {
	mu     sync.Mutex
	cmd    *exec.Cmd
	stdin  io.WriteCloser
	stdout *bufio.Scanner
	stderr *bytes.Buffer
	closed bool
}

// Start launches the compiled oracle binary at path. Close must be called
// when done — it kills the process rather than waiting for a clean exit,
// because spec/Main.agda's serve loop never terminates on its own (see
// that file's comment on why it doesn't need to detect EOF).
func Start(path string) (*Client, error) {
	cmd := exec.Command(path)
	// Strip an ambient LD_LIBRARY_PATH before exec'ing: a nix-built binary
	// dynamically links against nix's own glibc, and an unrelated
	// LD_LIBRARY_PATH set by other tooling on the host (CUDA, a Python
	// venv, whatever) can shadow it and crash the process with an
	// "undefined symbol" error at startup — the same class of problem
	// documented for invoking `agda` itself in this project's README.
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
	// Captured, not inherited: a crash at startup (the LD_LIBRARY_PATH case
	// the comment above describes) otherwise surfaces to a caller as a bare
	// "write: broken pipe" or "closed its output", with the actual reason
	// only visible if you happen to already be watching this process's fd 2.
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Start(); err != nil {
		_ = stdin.Close()
		return nil, fmt.Errorf("start oracle: %w", err)
	}
	scanner := bufio.NewScanner(stdout)
	return &Client{cmd: cmd, stdin: stdin, stdout: scanner, stderr: &stderr}, nil
}

// withoutLDLibraryPath drops LD_LIBRARY_PATH from an environment list
// (the os.Environ() "KEY=value" form) without disturbing anything else.
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

// Close terminates the oracle process. Safe to call more than once.
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

// States asks the oracle for its own state vocabulary — every string its
// parser accepts, in spec/Oracle.agda's own words (a list that file proves
// complete). The harness compares this to impl.AllStates before running
// anything else, so a rename or an added state on either side fails up
// front as "vocabulary drifted" rather than later as an InvalidState
// reply to a query that looked fine.
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

// Query asks the oracle what both policies decide for one state, given in
// wire form (impl.State's own string value — the vocabulary States checks).
func (c *Client) Query(state string) (OracleResponse, error) {
	line, err := c.roundTrip(state)
	if err != nil {
		return OracleResponse{}, err
	}
	// Pointers, not bools: an {"error":"InvalidState"} reply has to fail
	// here, not decode as a pair of confident falses.
	var r struct {
		AccessActive  *bool `json:"access_active"`
		BillingActive *bool `json:"billing_active"`
	}
	if err := json.Unmarshal([]byte(line), &r); err != nil || r.AccessActive == nil || r.BillingActive == nil {
		return OracleResponse{}, fmt.Errorf("oracle protocol: unexpected reply to %q: %q", state, line)
	}
	return OracleResponse{AccessActive: *r.AccessActive, BillingActive: *r.BillingActive}, nil
}

// roundTrip writes one line and reads one line back, serialized so two
// callers can't interleave on the single pipe pair.
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

// stderrSuffix appends whatever the oracle process wrote to stderr, if
// anything, so a startup crash names its own cause instead of just its
// symptom on the pipe.
func (c *Client) stderrSuffix() string {
	if c.stderr == nil || c.stderr.Len() == 0 {
		return ""
	}
	return fmt.Sprintf(" (oracle stderr: %s)", strings.TrimSpace(c.stderr.String()))
}
