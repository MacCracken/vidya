// Vidya — Reproducible Builds in OpenQASM (Determinism as a fixed basis state)
//
// A reproducible build is a PURE FUNCTION of its inputs: the same sources
// produce a byte-identical artifact on any machine, at any time. Run the
// build twice, hash the output twice, get the same digest. The defining
// property is DETERMINISM — zero dependence on hidden state (wall clock,
// directory iteration order, random temp names).
//
// OpenQASM cannot run a real compiler, but quantum measurement gives us a
// perfect physical model of "deterministic vs not":
//
//   • A circuit built from ONLY classical-reversible gates (X / CX / CCX)
//     drives the qubits to ONE fixed computational basis state. Measuring
//     that state yields the SAME bitstring on every shot — the quantum
//     echo of "same inputs -> same artifact digest, bit-for-bit." This is
//     the reproducible build.
//
//   • A Hadamard (h) creates a superposition: an equal blend of |0> and
//     |1>. Measuring collapses it randomly, so the result VARIES run to
//     run — the non-reproducible build that smuggled the wall clock (or
//     an unsorted readdir, or a random temp name) into the artifact.
//
// The fixed final basis state the reversible gates reach is, literally,
// the "content-addressed digest" that the deterministic inputs map to:
// inputs in, one fixed address out, idempotently.
//
// qelib1.inc gates only — no `swap`, no custom gates.

OPENQASM 2.0;
include "qelib1.inc";

// ── Two registers, two builds running side by side ────────────────────
//   det[0..2]  = the DETERMINISTIC build pipeline (reversible gates only)
//   ndet[0]    = the NON-DETERMINISTIC build (a leaked wall-clock bit)
//
// Each qubit reads |0> or |1>; the artifact "digest" is the measured
// bitstring. We want det to be constant across shots and ndet to vary.
qreg det[3];
qreg ndet[1];
creg digest[3];      // measured digest of the deterministic build
creg drift[1];       // measured bit of the non-deterministic build

// ── The two source inputs, encoded deterministically ──────────────────
// Think of det[0] and det[1] as two source files whose CONTENT is fixed.
// We set their content bits with X gates — a definite edit, no randomness.
//   det[0] = source "a.c"  content bit -> 1
//   det[1] = source "b.c"  content bit -> 1
// Same inputs every run, so these flips are identical every run.
x det[0];                 // input a.c : fixed content -> |1>
x det[1];                 // input b.c : fixed content -> |1>

// ── Sorted vs unsorted iteration, made irrelevant by determinism ──────
// A naive build folds files in readdir() order, which varies. The fix is
// to SORT filenames first so the fold order is fixed. We model the fold
// as CX gates writing each input's content into the digest qubit det[2].
// CX gates with distinct controls onto a common target COMMUTE (they are
// XOR accumulation), so applying them in either order — "a then b" or
// "b then a" — reaches the SAME basis state. That commutativity is the
// circuit-level statement of "sort the inputs and the digest stops caring
// about directory order."
cx det[0], det[2];        // fold input a.c into the running digest
cx det[1], det[2];        // fold input b.c into the running digest
                          // (swapping these two lines yields the same state)

// ── SOURCE_DATE_EPOCH: clamp the clock so "now" never leaks in ─────────
// A real build that embeds a timestamp differs every second. The fix is
// to clamp every timestamp to SOURCE_DATE_EPOCH — a FIXED value taken
// from the sources. We model "stamp the digest with the (clamped) build
// time" as a CCX: only when BOTH sources are present (det[0] & det[1])
// does the fixed epoch contribute its deterministic flip to the digest.
// Because the epoch is a constant, this gate fires the same way every run
// — no live clock, no drift.
ccx det[0], det[1], det[2];   // stamp clamped SOURCE_DATE_EPOCH into digest

// At this point det[] is in ONE fixed basis state. det[2] was flipped by
// two CX (1 XOR 1 = 0) then once by the CCX (0 XOR 1 = 1): a definite |1>.
// Every shot measures the SAME digest -> the build is reproducible.

// ── The non-reproducible build: a Hadamard leaks the wall clock ───────
// Now the counterexample. ndet[0] models a build that bakes the live
// wall-clock (or an unsorted hash-ordered readdir, or a random temp-file
// name) straight into the artifact. We represent that hidden entropy with
// a Hadamard: a 50/50 superposition with no fixed value.
h ndet[0];                // leaked entropy: artifact in superposition

// Measuring this bit gives 0 or 1 unpredictably — a different "digest"
// almost every run. Two builds from identical sources disagree. This is
// exactly the bug reproducible builds eliminate: the artifact depends on
// something that was never an input.

// ── Measure: read each build's digest ─────────────────────────────────
// digest[] (deterministic build) reads the SAME fixed bitstring on every
// shot — byte-identical artifacts, the reproducible-build guarantee.
// drift[0] (non-deterministic build) reads a random bit that varies shot
// to shot — the embedded-clock build that never reproduces.
measure det  -> digest;
measure ndet -> drift;

// ── Notes — the reproducible-build / quantum bridge ───────────────────
//
// Classical determinism:  artifact = f(inputs), pure. Achieved by
//                          (1) clamping timestamps to SOURCE_DATE_EPOCH,
//                          (2) sorting filesystem iteration order,
//                          (3) content-addressing artifact names by hash.
//                          Verify by building twice and diffing digests.
//
// Quantum analog:
//   • Reversible gates (X / CX / CCX) reach ONE fixed basis state, so
//     every measurement yields the same bitstring — same inputs, same
//     digest, bit-for-bit. The fixed state IS the content-addressed
//     output the inputs map to.
//   • Commuting CX gates onto a shared target = sorted-vs-unsorted input
//     order reaching the same digest (fold order made irrelevant).
//   • A constant-firing CCX = a clamped, fixed SOURCE_DATE_EPOCH stamp
//     that never drifts with the live clock.
//   • A Hadamard = leaked entropy (wall clock, hash-ordered readdir,
//     random temp name): superposition collapses to a value that varies
//     run to run — the non-reproducible build.
//
// Where the analogy stops: real reproducibility is about CONTENT hashing
// and byte-exact equality across machines; the circuit only models the
// determinism *property*, not the digest function. The classical ports
// remain ground truth — this file shows, physically, the difference
// between "computes one fixed answer" and "samples a random one."
