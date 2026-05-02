// Vidya — DNS in OpenQASM (record-table-as-superposition analog)
//
// Classical DNS: a hierarchical name → record table where each name
// resolves to one or more typed records (A, AAAA, CNAME, MX, TXT).
// CNAME chains let one name redirect to another; the resolver
// follows the chain until it hits a terminal record. The quantum
// analog is *qubit chaining via CNOT*: each CNAME is a CNOT from
// one qubit to the next, and the final A record is the qubit at the
// end of the chain.
//
// 4-qubit register represents a 3-step CNAME chain:
//   q[0] — origin name (e.g. www.example.com)
//   q[1] — first CNAME target
//   q[2] — second CNAME target
//   q[3] — terminal A record (the resolved IP)
//
// The CNOT chain models "follow the CNAME": measuring q[3] reveals
// the IP that q[0]'s name eventually resolves to. The transitive
// nature of entanglement IS the recursive lookup.
//
// In real quantum networking research, this maps onto *quantum
// routing tables*: a quantum router can hold an entangled superposition
// of next-hop addresses, and resolution collapses the chain to a
// single classical path — exactly the structure of DNS recursive
// resolution but with the lookup happening "all at once" in the
// register state rather than sequentially across hops.

OPENQASM 2.0;
include "qelib1.inc";

qreg q[4];
creg c[4];

// Origin name in superposition (could resolve to anywhere)
h q[0];

// CNAME chain: q[0] → q[1] → q[2] → q[3]
cx q[0], q[1];
cx q[1], q[2];
cx q[2], q[3];

// "Resolve" — measure all four; q[3] is the final answer
measure q -> c;
