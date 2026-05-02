// Vidya — Render Graph Architecture in OpenQASM (DAG-as-circuit analog)
//
// Classical render graph: a DAG of passes where each pass declares
// its reads and writes, and the framework topologically sorts and
// inserts barriers. The quantum analog is exactly a quantum circuit:
// gates are passes, qubits are resources, and the circuit's
// data-dependency DAG is the same DAG the render graph builds.
//
// 4-qubit register represents 4 resources (R0..R3). The 3-pass
// pipeline A→B→C from the cyrius reference maps to:
//
//   Pass A (writes R1)            — initialise q[1] (X gate)
//   Pass B (reads R1, writes R2)  — CNOT q[1] → q[2] (read R1, write R2)
//   Pass C (reads R2)             — measurement on q[2] depends on B
//
// The topological sort is implicit in the circuit's gate order:
// Qiskit's transpiler walks the same dependency DAG to determine
// scheduling and barrier insertion. This is exactly the structure
// render graphs build for GPU passes.
//
// Real quantum compilers (Qiskit's transpiler, t|ket>) maintain a
// DAG explicitly (DAGCircuit class) and the optimisation passes are
// graph rewrites over it — the same shape, different domain.

OPENQASM 2.0;
include "qelib1.inc";

qreg q[4];
creg c[4];

// Pass A: writes R1
x q[1];

// Pass B: reads R1, writes R2 (CNOT entangles them)
cx q[1], q[2];

// Pass C: reads R2 (measurement is the read)
measure q -> c;
