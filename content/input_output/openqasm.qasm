// Vidya — Input/Output in OpenQASM (Quantum State I/O)
//
// Quantum I/O: state preparation is "input" (writing data into
// qubits), measurement is "output" (reading data out). The circuit
// boundary is the I/O boundary — data enters as gate parameters
// and exits as classical measurement bits.

OPENQASM 2.0;
include "qelib1.inc";

// ── Input: state preparation (writing data into qubits) ───────────
qreg input[3];
creg input_out[3];

// Prepare the state |101> — this is "writing" classical data in
x input[0];           // bit 0 = 1
                       // bit 1 = 0 (default)
x input[2];           // bit 2 = 1

// ── Output: measurement (reading data from qubits) ────────────────
measure input -> input_out;
// Classical register input_out now holds the data

// ── Superposition input: encode probability distribution ──────────
qreg prob_in[2];
creg prob_out[2];

// Equal probability of all 4 states — "broadcast" input
h prob_in[0];
h prob_in[1];

measure prob_in -> prob_out;
// Output is probabilistic: 00, 01, 10, 11 each with 25%

// ── Entangled I/O: correlated output channels ──────────────────────
qreg epr[2];
creg epr_out[2];

h epr[0];
cx epr[0], epr[1];   // Bell pair
// Two output channels always agree: both 0 or both 1
measure epr -> epr_out;

// ── Circuit as I/O transform: input state → output state ──────────
// Every quantum circuit is a unitary transform: |in⟩ → U|in⟩
qreg transform[2];
creg transform_out[2];

// Input
x transform[0];       // prepare |10⟩

// Transform (SWAP)
cx transform[0], transform[1];
cx transform[1], transform[0];
cx transform[0], transform[1];

// Output
measure transform -> transform_out;
// Input was |10⟩, after SWAP output is |01⟩

// ── Classical output register: multiple measurements ──────────────
qreg multi[3];
creg out_a[1];
creg out_b[1];
creg out_c[1];

h multi[0];
cx multi[0], multi[1];
x multi[2];

// Separate output channels for different qubits
measure multi[0] -> out_a[0];
measure multi[1] -> out_b[0];
measure multi[2] -> out_c[0];
