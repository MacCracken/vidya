// Vidya — Framebuffer Rendering in OpenQASM (qubit-as-pixel analog)
//
// Classical framebuffer: a flat array of pixel cells, each in some
// color state, addressed by (x, y). The quantum analog is a *qubit
// register where each qubit represents one pixel*: the register's
// state vector encodes the entire framebuffer as a superposition of
// all possible pixel configurations.
//
// We use 4 qubits = a 2x2 framebuffer (4 pixels). Each qubit is one
// pixel; |0> means dark, |1> means lit. Operations:
//   - X gate    — "fb_set": flip pixel from |0> to |1>
//   - measure   — "fb_get": collapse and read pixel state
//
// The quantum framebuffer has one structural advantage over classical:
// because all pixels exist as a single entangled register, sub-grid
// effects (cellular automata, convolutions, region fills) can be
// expressed as gate sequences over the whole register at once. This
// is the structural argument for "GPU-as-quantum-processor": both
// fundamentally parallelize across the entire pixel grid in one shot,
// rather than per-pixel like the CPU framebuffer model.
//
// In real quantum image processing (Quantum Image Representations,
// FRQI, NEQR), this is exactly how images are encoded — each pixel
// is a basis state of a qubit register, and image transformations
// are unitary gate sequences.

OPENQASM 2.0;
include "qelib1.inc";

qreg q[4];
creg c[4];

// Initial state: all pixels dark (|0000>) — analog of fb_clear.

// fb_set: light pixels (0,0) and (1,1) — diagonal stripe
x q[0];     // pixel (0,0)
x q[3];     // pixel (1,1)

// "Draw horizontal line on row 0": pixel (0,0) and (1,0)
x q[1];     // pixel (1,0) — q[0] already lit

// fb_get: measure all four pixels
measure q -> c;
