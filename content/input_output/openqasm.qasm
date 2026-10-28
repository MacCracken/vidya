// Vidya — Input/Output in OpenQASM (Quantum State I/O)
//
// Quantum I/O: state preparation is "input" (writing data into
// qubits), measurement is "output" (reading data out). The circuit
// boundary is the I/O boundary — data enters as gate parameters
// and exits as classical measurement bits.

OPENQASM 3.1;
include "stdgates.inc";

// ── Input: state preparation (writing data into qubits) ───────────
qubit[3] input_q;
bit[3] input_out;

// Prepare the state |101> — this is "writing" classical data in
x input_q[0];           // bit 0 = 1
                       // bit 1 = 0 (default)
x input_q[2];           // bit 2 = 1

// ── Output: measurement (reading data from qubits) ────────────────
input_out = measure input_q;
// Classical register input_out now holds the data: 101 = 5
// @expect input_out == 5

// ── Superposition input: encode probability distribution ──────────
qubit[2] prob_in;
bit[2] prob_out;

// Equal probability of all 4 states — "broadcast" input
h prob_in[0];
h prob_in[1];

prob_out = measure prob_in;
// Output is probabilistic: 00, 01, 10, 11 each with 25%
// @expect prob_out in {0, 1, 2, 3}

// ── Entangled I/O: correlated output channels ──────────────────────
qubit[2] epr;
bit[2] epr_out;

h epr[0];
cx epr[0], epr[1];   // Bell pair
// Two output channels always agree: both 0 or both 1
epr_out = measure epr;
// @expect epr_out in {0, 3}

// ── Circuit as I/O transform: input state → output state ──────────
// Every quantum circuit is a unitary transform: |in⟩ → U|in⟩
qubit[2] transform;
bit[2] transform_out;

// Input
x transform[0];       // prepare |10⟩ (transform[0]=1, transform[1]=0)

// Transform (SWAP, spelled out as its 3 CNOTs; stdgates.inc's
// `swap transform[0], transform[1];` is the same unitary)
cx transform[0], transform[1];
cx transform[1], transform[0];
cx transform[0], transform[1];

// Output
transform_out = measure transform;
// Input was |10⟩, after SWAP output is |01⟩ (transform[1]=1: value 2)
// @expect transform_out == 2

// ── Classical output register: multiple measurements ──────────────
qubit[3] multi;
bit[1] out_a;
bit[1] out_b;
bit[1] out_c;

h multi[0];
cx multi[0], multi[1];
x multi[2];

// Separate output channels for different qubits
out_a[0] = measure multi[0];
out_b[0] = measure multi[1];
out_c[0] = measure multi[2];
// out_a and out_b are each 0 or 1 with equal probability and always
// agree (a Bell pair); out_c is 1 on every shot.
// @expect out_a in {0, 1}
// @expect out_b in {0, 1}
// @expect out_c == 1
